// Local test of the Margin Connector without Cloudflare: node connector/test.mjs
import assert from "node:assert/strict";
import worker, { MarginStore } from "./worker.js";
import { deriveKeys, open as openRecord, seal } from "./sync-crypto.mjs";

class MemoryStorage {
  map = new Map();
  async get(key) { return structuredClone(this.map.get(key)); }
  async put(key, value) { this.map.set(key, structuredClone(value)); }
  async delete(key) { this.map.delete(key); }
  // Like Durable Object storage: keys in order, `start` inclusive.
  async list({ prefix = "", start = "", limit = Infinity } = {}) {
    const keys = [...this.map.keys()].filter((k) => k.startsWith(prefix) && k >= start).sort().slice(0, limit);
    return new Map(keys.map((k) => [k, structuredClone(this.map.get(k))]));
  }
}

const stores = new Map();
const env = {
  STORE: {
    idFromName: (name) => name,
    get: (id) => {
      if (!stores.has(id)) stores.set(id, new MarginStore({ storage: new MemoryStorage() }, {}));
      const store = stores.get(id);
      return { fetch: (request) => store.fetch(request) };
    },
  },
};

const secret = "f".repeat(48);
const base = "https://margin.example.workers.dev";

async function request(path, body, method = "POST", headers = {}) {
  const response = await worker.fetch(
    new Request(base + path, { method, body: body ? JSON.stringify(body) : undefined, headers: { "content-type": "application/json", ...headers } }),
    env,
  );
  const type = response.headers.get("content-type") || "";
  const payload = type.includes("json") ? await response.json() : await response.text();
  return { status: response.status, payload };
}

const rpc = async (id, method, params) => (await request(`/mcp/${secret}`, { jsonrpc: "2.0", id, method, params })).payload;
const toolText = (reply) => reply.result.content[0].text;

// 1. Unknown or short secrets never reach a store.
assert.equal((await request("/mcp/short", { jsonrpc: "2.0", id: 1, method: "ping" })).payload, "Margin Connector läuft.");

// 2. Before the first sync Claude gets a helpful message.
const early = await rpc(1, "tools/call", { name: "get_overview", arguments: {} });
assert.equal(early.result.isError, true);
assert.match(toolText(early), /noch keine Daten/);

// 3. The phone uploads a snapshot.
const tools = [
  { name: "get_overview", inputSchema: { type: "object" }, annotations: { readOnlyHint: true } },
  { name: "list_tasks", inputSchema: { type: "object" }, annotations: { readOnlyHint: true } },
  { name: "list_notes", inputSchema: { type: "object" }, annotations: { readOnlyHint: true } },
  { name: "read_note", inputSchema: { type: "object" }, annotations: { readOnlyHint: true } },
  { name: "list_exams", inputSchema: { type: "object" }, annotations: { readOnlyHint: true } },
  { name: "add_task", inputSchema: { type: "object" }, annotations: { readOnlyHint: false } },
];
const snapshot = {
  syncedAt: "Montag, 2. November, 18:00",
  today: "2026-11-02",
  allowWrites: false,
  instructions: "Margin ist die Schul-App.",
  tools,
  data: {
    overview: { today: "2026-11-02 (Mo.)", open_tasks: 2 },
    tasks: [
      { id: "1", title: "S. 42 Nr. 3", subject: "Mathematik", status: "open", overdue: false },
      { id: "2", title: "Referat", subject: "Biologie", status: "open", overdue: true },
      { id: "3", title: "Alt", subject: "Biologie", status: "done" },
    ],
    exams: [
      { id: "e1", title: "Klassenarbeit Mathematik", date: "2026-11-20 (Fr.)", readiness: 40 },
      { id: "e0", title: "Test Bio", date: "2026-10-01 (Do.)", readiness: 90 },
    ],
    notes: [{ id: "n1", title: "Zellen", subject: "Biologie", date: "02.11.2026" }],
  },
  notes: [{ id: "n1", title: "Zellen", subject: "Biologie", date: "02.11.2026", updated: 1, body: "Mitose :: Zellteilung" }],
};
assert.deepEqual((await request(`/sync/${secret}`, { snapshot })).payload, { ok: true, inbox: [] });

// 4. MCP handshake and tool listing (write tools hidden while writing is off).
const init = await rpc(2, "initialize", { protocolVersion: "2025-06-18" });
assert.equal(init.result.protocolVersion, "2025-06-18");
assert.equal((await request(`/mcp/${secret}`, { jsonrpc: "2.0", method: "notifications/initialized" })).status, 202);
const listed = await rpc(3, "tools/list", {});
assert.deepEqual(listed.result.tools.map((t) => t.name), ["get_overview", "list_tasks", "list_notes", "read_note", "list_exams"]);
assert.equal((await request(`/mcp/${secret}`, null, "GET")).status, 405);

// 5. Read tools answer from the snapshot.
const overview = JSON.parse(toolText(await rpc(4, "tools/call", { name: "get_overview", arguments: {} })));
assert.equal(overview.open_tasks, 2);
assert.equal(overview.data_as_of, "Montag, 2. November, 18:00");
const open = JSON.parse(toolText(await rpc(5, "tools/call", { name: "list_tasks", arguments: {} })));
assert.deepEqual(open.map((t) => t.id), ["1", "2"]);
const overdueBio = JSON.parse(toolText(await rpc(6, "tools/call", { name: "list_tasks", arguments: { status: "overdue", subject: "bio" } })));
assert.deepEqual(overdueBio.map((t) => t.id), ["2"]);
const found = JSON.parse(toolText(await rpc(7, "tools/call", { name: "list_notes", arguments: { query: "mitose" } })));
assert.deepEqual(found.map((n) => n.id), ["n1"]);
const note = JSON.parse(toolText(await rpc(8, "tools/call", { name: "read_note", arguments: { id: "n1" } })));
assert.equal(note.body, "Mitose :: Zellteilung");
const exams = JSON.parse(toolText(await rpc(9, "tools/call", { name: "list_exams", arguments: {} })));
assert.deepEqual(exams.map((e) => e.id), ["e1"], "past exams are hidden by default");

// 6. Writes are refused while not allowed …
const refused = await rpc(10, "tools/call", { name: "add_task", arguments: { title: "Vokabeln" } });
assert.equal(refused.result.isError, true);

// 7. … and queued once allowed; the phone gets them on the next sync and confirms them.
await request(`/sync/${secret}`, { snapshot: { ...snapshot, allowWrites: true } });
const queued = JSON.parse(toolText(await rpc(11, "tools/call", { name: "add_task", arguments: { title: "Vokabeln" } })));
assert.equal(queued.queued, true);
const pending = (await request(`/sync/${secret}`, {})).payload.inbox;
assert.equal(pending.length, 1);
assert.equal(pending[0].tool, "add_task");
assert.deepEqual(pending[0].args, { title: "Vokabeln" });
assert.deepEqual((await request(`/sync/${secret}`, { acked: [pending[0].id] })).payload.inbox, []);

// 8. Deleted notes disappear; the web view renders.
await request(`/sync/${secret}`, { snapshot: { ...snapshot, notes: [] } });
const gone = await rpc(12, "tools/call", { name: "read_note", arguments: { id: "n1" } });
assert.equal(gone.result.isError, true);
const page = await request(`/view/${secret}`, null, "GET");
assert.match(page.payload, /Klassenarbeit Mathematik/);
assert.doesNotMatch(page.payload, /Test Bio/);

// 9. Unknown methods get a JSON-RPC error.
assert.equal((await rpc(13, "resources/list", {})).error.code, -32601);

console.log("Margin Connector: all checks passed");

// ---------------------------------------------------------------- end-to-end encrypted sync

{
// 10. Test vectors: every client (Dart, Swift) must derive the same key and token.
const keys = await deriveKeys("  korrekt pferd batterie heftklammer ");
assert.equal(Buffer.from(keys.key).toString("hex"), "5314c46262f08cedf6afdcada238475fa37dab724ff206447c0af0298d91bcca");
assert.equal(keys.vault, "eb4bb41576e9e67496a94611417ced57ac85c8bca9acee6324ef625b01b9d55d");
const vectorUid = "8D0B9F5E-2B7C-4C1A-9E3F-1A2B3C4D5E6F";
const vectorBlob = "AAECAwQFBgcICQoLgqL/ULm19SQ4qQ4ZIiRuTzyqKi6QXSp/6G3JfKhLQZzMSSL1yj4uClzgkjDoqLGuA9uXosmWg7Q24zfCl9Rc3HEsDCt22BmKn7HVXA+Odp6f7xom4YdfmA6gwER4MdxXbeMbdXKLWW8jQ3Pn8mIaAGFBSwLcatom4r5VSHT9C9lk";
const vectorPayload = { type: "task", deleted: false, data: { uid: vectorUid, title: "S. 42 Nr. 3" } };
assert.equal(await seal(keys.key, vectorUid, 1762160400000, vectorPayload, new Uint8Array(12).map((_, i) => i)), vectorBlob);
assert.deepEqual(await openRecord(keys.key, vectorUid, 1762160400000, vectorBlob), { v: 1, ...vectorPayload });
// A changed timestamp, uid or key makes the record unreadable (AAD binds uid and updatedAt).
await assert.rejects(openRecord(keys.key, vectorUid, 1762160400001, vectorBlob));
await assert.rejects(openRecord(keys.key, "ANOTHER-UID", 1762160400000, vectorBlob));
await assert.rejects(openRecord((await deriveKeys("falsch")).key, vectorUid, 1762160400000, vectorBlob));

const auth = { Authorization: "Bearer " + keys.vault };
const push = async (records, headers = auth) => request("/e2e/push", { records }, "POST", headers);
const pull = async (since, limit) => request(`/e2e/pull?since=${since}${limit ? "&limit=" + limit : ""}`, null, "GET", auth);
const record = async (uid, updatedAt, type, data, deleted = false) =>
  ({ uid, updatedAt, blob: await seal(keys.key, uid, updatedAt, { type, deleted, data }) });

// 11. Without a well-formed token nothing reaches a vault.
assert.equal((await push([], {})).status, 401);
assert.equal((await push([], { Authorization: "Bearer abc" })).status, 401);
assert.equal((await request("/e2e/push", { nope: 1 }, "POST", auth)).status, 400);
assert.deepEqual((await request("/e2e/info", null, "GET", auth)).payload, { records: 0, cursor: 0 });

// 12. A phone pushes three records; the server only sees ciphertext.
const subject = await record("S1", 1000, "subject", { uid: "S1", name: "Mathematik", colorKey: "blue" });
const task = await record("T1", 1000, "task", { uid: "T1", title: "S. 42 Nr. 3", subject: "S1" });
const note = await record("N1", 1000, "note", { uid: "N1", title: "Zellen", body: "Mitose :: Zellteilung" });
const first = (await push([subject, task, note])).payload;
assert.deepEqual(first.accepted, ["S1", "T1", "N1"]);
assert.equal(first.cursor, 3);
const vaultStore = stores.get("vault:" + keys.vault);
const stored = JSON.stringify([...vaultStore.ctx.storage.map.values()]);
assert.doesNotMatch(stored, /Mathematik|Zellteilung|S\. 42/, "server stores no plaintext");

// 13. A second device pulls everything and decrypts it.
const all = (await pull(0)).payload;
assert.equal(all.cursor, 3);
assert.equal(all.more, false);
const opened = await Promise.all(all.records.map((r) => openRecord(keys.key, r.uid, r.updatedAt, r.blob)));
assert.deepEqual(opened.map((r) => r.type), ["subject", "task", "note"]);
assert.equal(opened[1].data.title, "S. 42 Nr. 3");

// 14. Last write wins: older or equal versions are rejected, newer ones replace.
const stale = (await push([await record("T1", 900, "task", { uid: "T1", title: "alt" }), await record("T1", 1000, "task", { uid: "T1", title: "gleich" })])).payload;
assert.deepEqual(stale.accepted, []);
assert.deepEqual(stale.rejected.map((r) => [r.uid, r.reason, r.updatedAt]), [["T1", "stale", 1000], ["T1", "stale", 1000]]);
const newer = (await push([await record("T1", 2000, "task", { uid: "T1", title: "S. 42 Nr. 3 und 4" })])).payload;
assert.deepEqual(newer.accepted, ["T1"]);
assert.equal(newer.cursor, 4);

// 15. Pull since a cursor only returns what changed; the replaced change entry is gone.
const changed = (await pull(3)).payload;
assert.deepEqual(changed.records.map((r) => [r.uid, r.updatedAt]), [["T1", 2000]]);
assert.equal(changed.cursor, 4);
assert.deepEqual((await pull(4)).payload, { records: [], cursor: 4, more: false });
assert.deepEqual((await pull(0)).payload.records.map((r) => r.uid), ["S1", "N1", "T1"]);

// 16. Deletes are encrypted tombstones (the server cannot forge or tell them apart).
assert.deepEqual((await push([await record("N1", 3000, "note", { uid: "N1" }, true)])).payload.accepted, ["N1"]);
const tombstone = (await pull(4)).payload.records[0];
assert.equal((await openRecord(keys.key, tombstone.uid, tombstone.updatedAt, tombstone.blob)).deleted, true);

// 17. Paging: limit and `more` let a new device catch up in chunks.
await push(await Promise.all(Array.from({ length: 7 }, (_, i) => record("P" + i, 5000 + i, "pin", { uid: "P" + i }))));
const page1 = (await pull(0, 4)).payload;
assert.equal(page1.records.length, 4);
assert.equal(page1.more, true);
const page2 = (await pull(page1.cursor, 4)).payload;
const page3 = (await pull(page2.cursor, 4)).payload;
assert.equal(page3.more, false);
const seen = [...page1.records, ...page2.records, ...page3.records].map((r) => r.uid);
assert.deepEqual(seen.sort(), ["N1", "P0", "P1", "P2", "P3", "P4", "P5", "P6", "S1", "T1"]);
assert.deepEqual((await request("/e2e/info", null, "GET", auth)).payload, { records: 10, cursor: 12 });

// 18. Invalid and oversized records are refused one by one, the rest still goes through.
const mixed = (await push([
  { uid: "../x", updatedAt: 1, blob: "a" },
  { uid: "X1", updatedAt: "soon", blob: "a" },
  { uid: "X2", updatedAt: 1, blob: "a".repeat(2_000_000) },
  await record("X3", 1, "subject", { uid: "X3" }),
])).payload;
assert.deepEqual(mixed.rejected.map((r) => r.reason), ["invalid", "invalid", "tooLarge"]);
assert.deepEqual(mixed.accepted, ["X3"]);
assert.equal((await push(Array.from({ length: 201 }, () => subject))).status, 413);

// 19. Another passphrase is another vault: nothing leaks across.
const other = await deriveKeys("ein ganz anderer satz");
const foreign = await request("/e2e/pull?since=0", null, "GET", { Authorization: "Bearer " + other.vault });
assert.deepEqual(foreign.payload.records, []);

console.log("Margin Sync: all checks passed");
}
