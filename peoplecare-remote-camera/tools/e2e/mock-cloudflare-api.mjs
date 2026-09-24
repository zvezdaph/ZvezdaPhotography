// MOCK of the Cloudflare Stream Live Input API, for the local end-to-end check
// only (tools/e2e/run_e2e.sh). Real credentials cannot live in the repository,
// so the Worker under test is pointed at this server with CLOUDFLARE_API_BASE.
// It implements the subset used by the Worker, with the response envelope and
// the live input fields documented by Cloudflare. It never carries video.
//
//   POST   /client/v4/accounts/:account/stream/live_inputs
//   GET    /client/v4/accounts/:account/stream/live_inputs/:uid
//   PUT    /client/v4/accounts/:account/stream/live_inputs/:uid
//   DELETE /client/v4/accounts/:account/stream/live_inputs/:uid
//   POST   /client/v4/accounts/:account/stream/live_inputs/:uid/rotate_keys
//   GET    /client/v4/accounts/:account/stream/live_inputs/:uid/videos
//   POST   /__mock/status {"uid", "status"}   test hook: connection status seen by "Cloudflare"
import { createServer } from "node:http";
import { randomBytes } from "node:crypto";

const port = Number(process.env.MOCK_PORT ?? 8788);
const token = process.env.MOCK_API_TOKEN ?? "e2e-api-token";
const inputs = new Map();
const hex = (n) => randomBytes(n).toString("hex");

function keys(uid) {
  return {
    srt: { url: "srt://127.0.0.1:9710", streamId: `${uid}${hex(8)}`, passphrase: hex(16) },
    srtPlayback: { url: "srt://127.0.0.1:9710", streamId: `play${uid}${hex(8)}`, passphrase: hex(16) },
    rtmps: { url: "rtmps://127.0.0.1:4443/live/", streamKey: `${hex(16)}k${uid}` },
    rtmpsPlayback: { url: "rtmps://127.0.0.1:4443/live/", streamKey: `${hex(16)}p${uid}` },
  };
}

function send(res, status, body) {
  res.writeHead(status, { "Content-Type": "application/json" });
  res.end(JSON.stringify(body));
}

async function readBody(req) {
  let raw = "";
  for await (const chunk of req) raw += chunk;
  return raw ? JSON.parse(raw) : {};
}

createServer(async (req, res) => {
  const url = new URL(req.url, `http://127.0.0.1:${port}`);
  if (url.pathname === "/__mock/status" && req.method === "POST") {
    const { uid, status } = await readBody(req);
    const input = inputs.get(uid);
    if (!input) return send(res, 404, { ok: false });
    input.status = status;
    return send(res, 200, { ok: true });
  }
  if (url.pathname === "/__mock/inputs") return send(res, 200, [...inputs.values()]);
  if (req.headers.authorization !== `Bearer ${token}`) {
    return send(res, 401, { success: false, errors: [{ code: 10000, message: "Authentication error" }], result: null });
  }
  const m = /^\/client\/v4\/accounts\/[^/]+\/stream\/live_inputs(?:\/([0-9a-f]{32}))?(\/rotate_keys|\/videos)?$/.exec(url.pathname);
  if (!m) return send(res, 404, { success: false, errors: [{ code: 7003, message: "No route" }], result: null });
  const [, uid, sub] = m;
  if (!uid && req.method === "POST") {
    const body = await readBody(req);
    const id = hex(16);
    const input = {
      uid: id,
      created: new Date().toISOString(),
      modified: new Date().toISOString(),
      meta: body.meta ?? {},
      recording: body.recording ?? { mode: "off" },
      enabled: body.enabled ?? true,
      deleteRecordingAfterDays: body.deleteRecordingAfterDays ?? null,
      preferLowLatency: body.preferLowLatency ?? false,
      status: null,
      ...keys(id),
    };
    inputs.set(id, input);
    return send(res, 200, { success: true, errors: [], messages: [], result: input });
  }
  const input = uid ? inputs.get(uid) : null;
  if (!input) return send(res, 404, { success: false, errors: [{ code: 10003, message: "Live input not found" }], result: null });
  if (sub === "/rotate_keys" && req.method === "POST") {
    Object.assign(input, keys(uid), { keysRotatedAt: new Date().toISOString() });
    return send(res, 200, { success: true, errors: [], messages: [], result: input });
  }
  if (sub === "/videos" && req.method === "GET") return send(res, 200, { success: true, errors: [], messages: [], result: [] });
  if (!sub && req.method === "GET") return send(res, 200, { success: true, errors: [], messages: [], result: input });
  if (!sub && req.method === "PUT") {
    const body = await readBody(req);
    if (typeof body.enabled === "boolean") input.enabled = body.enabled;
    input.modified = new Date().toISOString();
    return send(res, 200, { success: true, errors: [], messages: [], result: input });
  }
  if (!sub && req.method === "DELETE") {
    inputs.delete(uid);
    res.writeHead(200).end();
    return;
  }
  return send(res, 405, { success: false, errors: [{ code: 10405, message: "Method not allowed" }], result: null });
}).listen(port, "127.0.0.1", () => console.log(`[mock-cloudflare-api] http://127.0.0.1:${port}`));
