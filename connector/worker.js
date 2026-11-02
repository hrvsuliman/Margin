// Margin Connector – a tiny relay on your own Cloudflare account.
//
// Claude (claude.ai, the Claude apps, Claude Code) talks MCP to this Worker.
// The Margin app on your iPhone regularly uploads a snapshot of its data and
// picks up the changes Claude asked for. Nothing else is stored here.
//
// Routes (SECRET = the long random key shown in Margin):
//   POST /sync/SECRET   iPhone → snapshot up, pending changes down
//   POST /mcp/SECRET    MCP endpoint for Claude (Streamable HTTP, JSON responses)
//   GET  /view/SECRET   read-only web page of your data (for the PC)

const SUPPORTED_VERSIONS = ["2025-11-25", "2025-06-18", "2025-03-26"];

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const [kind, secret] = url.pathname.split("/").filter(Boolean);
    if (!["sync", "mcp", "view"].includes(kind) || !secret || secret.length < 32) {
      return new Response("Margin Connector läuft.", { status: 200 });
    }
    const store = env.STORE.get(env.STORE.idFromName(secret));
    return store.fetch(request);
  },
};

export class MarginStore {
  constructor(ctx, env) {
    this.ctx = ctx;
    this.env = env;
  }

  async fetch(request) {
    const kind = new URL(request.url).pathname.split("/").filter(Boolean)[0];
    try {
      if (kind === "sync") return await this.sync(request);
      if (kind === "mcp") return await this.mcp(request);
      if (kind === "view") return await this.view();
    } catch (error) {
      return json({ error: String(error) }, 500);
    }
    return new Response("Not found", { status: 404 });
  }

  // ---------------------------------------------------------------- sync

  async sync(request) {
    if (request.method !== "POST") return new Response(null, { status: 405 });
    const body = await request.json();
    const storage = this.ctx.storage;

    if (body.snapshot) {
      const { notes = [], ...core } = body.snapshot;
      await storage.put("core", core);
      // Notes are stored one by one (large ones would not fit into one value).
      const known = (await storage.get("noteIndex")) || {};
      const next = {};
      for (const note of notes) {
        next[note.id] = note.updated;
        if (known[note.id] !== note.updated) await storage.put("note:" + note.id, note);
      }
      for (const id of Object.keys(known)) {
        if (!(id in next)) await storage.delete("note:" + id);
      }
      await storage.put("noteIndex", next);
    }

    let inbox = (await storage.get("inbox")) || [];
    if (Array.isArray(body.acked) && body.acked.length) {
      inbox = inbox.filter((item) => !body.acked.includes(item.id));
      await storage.put("inbox", inbox);
    }
    return json({ ok: true, inbox });
  }

  // ---------------------------------------------------------------- MCP

  async mcp(request) {
    if (request.method !== "POST") {
      return new Response(null, { status: 405, headers: { Allow: "POST" } });
    }
    const message = await request.json();
    if (message.id === undefined || message.id === null) {
      return new Response(null, { status: 202 }); // notification
    }
    const core = await this.ctx.storage.get("core");
    const reply = (result) => json({ jsonrpc: "2.0", id: message.id, result });

    switch (message.method) {
      case "initialize": {
        const requested = message.params?.protocolVersion;
        return reply({
          protocolVersion: SUPPORTED_VERSIONS.includes(requested) ? requested : SUPPORTED_VERSIONS[1],
          capabilities: { tools: { listChanged: false } },
          serverInfo: { name: "margin", title: "Margin", version: "1.0" },
          instructions:
            (core?.instructions || "Margin ist eine Schul-App.") +
            " Die Daten stammen aus dem letzten Abgleich mit dem iPhone (siehe data_as_of). " +
            "Änderungen werden vorgemerkt und übernommen, sobald Margin auf dem iPhone geöffnet wird.",
        });
      }
      case "ping":
        return reply({});
      case "tools/list": {
        const tools = (core?.tools || []).filter((tool) => core.allowWrites || tool.annotations?.readOnlyHint);
        return reply({ tools });
      }
      case "tools/call":
        return reply(await this.callTool(message.params?.name, message.params?.arguments || {}, core));
      default:
        return json({ jsonrpc: "2.0", id: message.id, error: { code: -32601, message: "Method not found" } });
    }
  }

  async callTool(name, args, core) {
    if (!core) {
      return text("Margin hat noch keine Daten gesendet. Öffne Margin auf dem iPhone (Tutor › Claude-Connector › Jetzt abgleichen).", true);
    }
    const tool = (core.tools || []).find((t) => t.name === name);
    if (!tool) return text("Unbekanntes Werkzeug: " + name, true);

    const storage = this.ctx.storage;
    const inbox = (await storage.get("inbox")) || [];

    if (!tool.annotations?.readOnlyHint) {
      if (!core.allowWrites) {
        return text("Änderungen sind in Margin gerade nicht erlaubt (Tutor › Claude-Connector › Änderungen erlauben).", true);
      }
      const id = crypto.randomUUID();
      inbox.push({ id, tool: name, args, createdAt: new Date().toISOString() });
      await storage.put("inbox", inbox);
      return ok({
        queued: true,
        id,
        hinweis: "Vorgemerkt. Margin übernimmt die Änderung beim nächsten Abgleich (wenn die App geöffnet wird).",
      });
    }

    const data = core.data || {};
    const matches = (value, query) =>
      !query || String(value || "").toLowerCase().includes(String(query).toLowerCase());

    switch (name) {
      case "get_overview":
        return ok({ ...data.overview, data_as_of: core.syncedAt, pending_changes: inbox.length });
      case "list_tasks": {
        const status = args.status || "open";
        const tasks = (data.tasks || []).filter((task) => {
          if (!matches(task.subject, args.subject)) return false;
          if (status === "all") return true;
          if (status === "done") return task.status === "done";
          if (status === "overdue") return task.overdue === true;
          return task.status !== "done";
        });
        return ok(tasks);
      }
      case "list_exams": {
        const today = core.today || "";
        return ok((data.exams || []).filter((exam) => args.include_past || String(exam.date).slice(0, 10) >= today));
      }
      case "get_timetable":
        return ok(data.timetable || {});
      case "list_topics": {
        const subjects = Object.keys(data.topics || {});
        const subject = subjects.find((s) => s.toLowerCase() === String(args.subject || "").toLowerCase())
          || subjects.find((s) => matches(s, args.subject));
        if (!subject) return text("Fach nicht gefunden. Vorhandene Fächer: " + subjects.join(", "), true);
        return ok(data.topics[subject]);
      }
      case "list_notes": {
        const index = data.notes || [];
        const results = [];
        for (const note of index) {
          if (!matches(note.subject, args.subject)) continue;
          if (args.query) {
            const full = await storage.get("note:" + note.id);
            if (!matches(note.title, args.query) && !matches(full?.body, args.query)) continue;
          }
          results.push(note);
        }
        return ok(results.slice(0, 40));
      }
      case "read_note": {
        const note = await storage.get("note:" + args.id);
        if (!note) return text("Notiz nicht gefunden. Nutze list_notes für gültige ids.", true);
        return ok({ title: note.title, date: note.date, subject: note.subject, body: note.body });
      }
      case "list_flashcards":
        return ok((data.cards || []).filter((card) => matches(card.subject, args.subject) && (!args.due_only || card.due)).slice(0, 150));
      case "get_study_stats":
        return ok(data.stats || {});
      default:
        return text("Dieses Werkzeug ist über den Connector nicht verfügbar.", true);
    }
  }

  // ---------------------------------------------------------------- web view

  async view() {
    const core = await this.ctx.storage.get("core");
    if (!core) return html("<p>Noch keine Daten. Öffne Margin auf dem iPhone und gleiche ab.</p>");
    const data = core.data || {};
    const esc = (value) => String(value ?? "").replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);
    const tasks = (data.tasks || []).filter((t) => t.status !== "done");
    const exams = (data.exams || []).filter((e) => String(e.date).slice(0, 10) >= (core.today || ""));
    const notes = [];
    for (const entry of (data.notes || []).slice(0, 60)) {
      const note = await this.ctx.storage.get("note:" + entry.id);
      if (note) notes.push(note);
    }
    const timetable = Object.entries(data.timetable || {});
    return html(`
      <h1>Margin</h1>
      <p class="muted">Stand: ${esc(core.syncedAt)}</p>
      <h2>Aufgaben</h2>
      <ul>${tasks.map((t) => `<li><b>${esc(t.title)}</b> <span class="muted">${esc(t.subject || "")} ${esc(t.due || "")}</span>${t.overdue ? ' <span class="red">überfällig</span>' : ""}</li>`).join("") || "<li class='muted'>Nichts offen</li>"}</ul>
      <h2>Prüfungen</h2>
      <ul>${exams.map((e) => `<li><b>${esc(e.title)}</b> <span class="muted">${esc(e.date)} · vorbereitet ${esc(e.readiness)} %</span></li>`).join("") || "<li class='muted'>Keine</li>"}</ul>
      <h2>Stundenplan</h2>
      ${timetable.map(([day, lessons]) => `<h3>${esc(day)}</h3><ul>${lessons.map((l) => `<li>${esc(l)}</li>`).join("")}</ul>`).join("")}
      <h2>Notizen</h2>
      ${notes.map((n) => `<details><summary><b>${esc(n.title)}</b> <span class="muted">${esc(n.subject || "")} ${esc(n.date)}</span></summary><pre>${esc(n.body)}</pre></details>`).join("")}
    `);
  }
}

function json(value, status = 200) {
  return new Response(JSON.stringify(value), { status, headers: { "Content-Type": "application/json" } });
}

function ok(value) {
  return { content: [{ type: "text", text: JSON.stringify(value) }], isError: false };
}

function text(message, isError = false) {
  return { content: [{ type: "text", text: message }], isError };
}

function html(body) {
  return new Response(
    `<!doctype html><html lang="de"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
     <title>Margin</title><style>
       body { font: 16px/1.5 -apple-system, system-ui, sans-serif; max-width: 760px; margin: 0 auto; padding: 24px 16px; background: #f6f3ec; color: #1c1b1f; }
       h1, h2, h3 { font-family: Georgia, serif; } h1 { border-left: 3px solid #d4513b; padding-left: 12px; }
       .muted { color: #6b6862; font-size: 14px; } .red { color: #d4513b; }
       pre { white-space: pre-wrap; font-family: inherit; background: #fffdf8; padding: 12px; border-radius: 8px; }
       @media (prefers-color-scheme: dark) { body { background: #131315; color: #ece9e2; } pre { background: #1d1d20; } }
     </style></head><body>${body}</body></html>`,
    { headers: { "Content-Type": "text/html; charset=utf-8" } },
  );
}
