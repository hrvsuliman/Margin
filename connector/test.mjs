// Local test of the Margin Connector without Cloudflare: node connector/test.mjs
import assert from "node:assert/strict";
import worker, { MarginStore } from "./worker.js";

class MemoryStorage {
  map = new Map();
  async get(key) { return structuredClone(this.map.get(key)); }
  async put(key, value) { this.map.set(key, structuredClone(value)); }
  async delete(key) { this.map.delete(key); }
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

async function request(path, body, method = "POST") {
  const response = await worker.fetch(
    new Request(base + path, { method, body: body ? JSON.stringify(body) : undefined, headers: { "content-type": "application/json" } }),
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
