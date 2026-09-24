import { SELF } from "cloudflare:test";
import { vi } from "vitest";

export const ORIGIN = "https://studio.test";
export const PASSWORD = "test-password-0123";
const API_PREFIX = "https://cf-api.test/client/v4/accounts/test-account-id/stream/live_inputs";

let ipCounter = 0;
/** Every test uses its own client IP so that the per-IP rate limits never interfere. */
export function nextIp(): string {
  ipCounter++;
  return `10.${Math.floor(ipCounter / 250) % 250}.${ipCounter % 250}.7`;
}

export interface FakeLiveInput {
  uid: string;
  enabled: boolean;
  status: unknown;
  meta: Record<string, unknown>;
  recording: Record<string, unknown>;
  srt: { url: string; streamId: string; passphrase: string };
  srtPlayback: { url: string; streamId: string; passphrase: string };
  rtmps: { url: string; streamKey: string };
  rtmpsPlayback: { url: string; streamKey: string };
  keysRotatedAt?: string;
}

function hex(bytes: number): string {
  const data = new Uint8Array(bytes);
  crypto.getRandomValues(data);
  return Array.from(data, (b) => b.toString(16).padStart(2, "0")).join("");
}

/**
 * In-memory fake of the Cloudflare Stream Live Input API, installed as a
 * fetch mock. Hostnames are fake (".invalid"): tests never reach Cloudflare.
 */
export class FakeStreamApi {
  readonly inputs = new Map<string, FakeLiveInput>();
  readonly calls: Array<{ method: string; path: string; body: unknown }> = [];
  failNext: number | null = null;

  install(): void {
    const original = globalThis.fetch;
    vi.spyOn(globalThis, "fetch").mockImplementation(async (input: RequestInfo | URL, init?: RequestInit) => {
      const request = new Request(input as RequestInfo, init);
      if (!request.url.startsWith(API_PREFIX)) return original(input as RequestInfo, init);
      return this.handle(request);
    });
  }

  private credentials(uid: string) {
    return {
      srt: { url: "srt://live.cf-test.invalid:778", streamId: uid, passphrase: hex(16) },
      srtPlayback: { url: "srt://live.cf-test.invalid:778", streamId: `play${uid}`, passphrase: hex(16) },
      rtmps: { url: "rtmps://live.cf-test.invalid:443/live/", streamKey: hex(24) },
      rtmpsPlayback: { url: "rtmps://live.cf-test.invalid:443/live/", streamKey: hex(24) },
    };
  }

  private async handle(request: Request): Promise<Response> {
    const path = request.url.slice(API_PREFIX.length);
    const body = request.method === "GET" || request.method === "DELETE" ? null : await request.text().then((t) => (t ? JSON.parse(t) : null));
    this.calls.push({ method: request.method, path, body });
    if (request.headers.get("Authorization") !== "Bearer test-api-token") {
      return Response.json({ success: false, errors: [{ code: 10000, message: "Authentication error" }] }, { status: 403 });
    }
    if (this.failNext !== null) {
      const status = this.failNext;
      this.failNext = null;
      return Response.json({ success: false, errors: [{ code: 10001, message: "Simulated failure" }] }, { status });
    }
    const ok = (result: unknown) => Response.json({ success: true, errors: [], messages: [], result });
    const notFound = () => Response.json({ success: false, errors: [{ code: 10003, message: "Not found" }] }, { status: 404 });

    if (path === "" && request.method === "POST") {
      const uid = hex(16);
      const input: FakeLiveInput = {
        uid,
        enabled: true,
        status: null,
        meta: (body as { meta?: Record<string, unknown> })?.meta ?? {},
        recording: (body as { recording?: Record<string, unknown> })?.recording ?? {},
        ...this.credentials(uid),
      };
      this.inputs.set(uid, input);
      return ok(input);
    }
    const match = /^\/([0-9a-f]{32})(\/rotate_keys|\/videos)?$/.exec(path);
    if (!match) return notFound();
    const input = this.inputs.get(match[1]);
    if (!input) return notFound();
    if (match[2] === "/rotate_keys" && request.method === "POST") {
      Object.assign(input, this.credentials(input.uid), { keysRotatedAt: new Date().toISOString() });
      return ok(input);
    }
    if (match[2] === "/videos" && request.method === "GET") return ok([]);
    if (!match[2] && request.method === "GET") return ok(input);
    if (!match[2] && request.method === "PUT") {
      if (typeof (body as { enabled?: unknown })?.enabled === "boolean") input.enabled = (body as { enabled: boolean }).enabled;
      return ok(input);
    }
    if (!match[2] && request.method === "DELETE") {
      this.inputs.delete(input.uid);
      return new Response(null, { status: 200 });
    }
    return notFound();
  }
}

export async function api(
  path: string,
  options: { method?: string; body?: unknown; cookie?: string; ip?: string; origin?: string | null; headers?: Record<string, string> } = {},
): Promise<Response> {
  const headers: Record<string, string> = { ...(options.headers ?? {}) };
  if (options.body !== undefined) headers["Content-Type"] = "application/json";
  if (options.cookie) headers.Cookie = options.cookie;
  headers["CF-Connecting-IP"] = options.ip ?? nextIp();
  if (options.origin !== null) headers.Origin = options.origin ?? ORIGIN;
  return SELF.fetch(`${ORIGIN}${path}`, {
    method: options.method ?? (options.body !== undefined ? "POST" : "GET"),
    headers,
    body: options.body !== undefined ? JSON.stringify(options.body) : undefined,
  });
}

export async function login(operator = "Regista"): Promise<string> {
  const response = await api("/api/auth/login", { body: { password: PASSWORD, operator } });
  if (response.status !== 200) throw new Error(`login failed: ${response.status} ${await response.text()}`);
  const setCookie = response.headers.get("Set-Cookie") ?? "";
  const match = /pcrc_session=([^;]+)/.exec(setCookie);
  if (!match) throw new Error("no session cookie");
  return `pcrc_session=${match[1]}`;
}

export class SocketClient {
  readonly messages: Array<Record<string, unknown>> = [];
  private waiters: Array<() => void> = [];
  closed: { code: number; reason: string } | null = null;

  constructor(readonly ws: WebSocket) {
    ws.accept();
    ws.addEventListener("message", (event) => {
      this.messages.push(JSON.parse(event.data as string));
      this.wake();
    });
    ws.addEventListener("close", (event) => {
      this.closed = { code: event.code, reason: event.reason };
      this.wake();
    });
  }

  private wake() {
    const waiters = this.waiters;
    this.waiters = [];
    for (const w of waiters) w();
  }

  send(message: unknown): void {
    this.ws.send(JSON.stringify(message));
  }

  /** Waits for (and consumes) the first message matching the predicate. */
  async next(predicate: (m: Record<string, unknown>) => boolean, timeoutMs = 3000): Promise<Record<string, unknown>> {
    const deadline = Date.now() + timeoutMs;
    for (;;) {
      const index = this.messages.findIndex(predicate);
      if (index >= 0) return this.messages.splice(index, 1)[0];
      if (this.closed) throw new Error(`socket closed (${this.closed.code} ${this.closed.reason}) while waiting`);
      if (Date.now() > deadline) throw new Error(`timeout waiting for message; got ${JSON.stringify(this.messages.map((m) => m.type))}`);
      await new Promise<void>((resolve) => {
        const timer = setTimeout(resolve, 50);
        this.waiters.push(() => {
          clearTimeout(timer);
          resolve();
        });
      });
    }
  }

  nextType(type: string, timeoutMs?: number) {
    return this.next((m) => m.type === type, timeoutMs);
  }

  async waitClosed(timeoutMs = 3000): Promise<{ code: number; reason: string }> {
    const deadline = Date.now() + timeoutMs;
    while (!this.closed) {
      if (Date.now() > deadline) throw new Error("socket not closed");
      await new Promise((r) => setTimeout(r, 25));
    }
    return this.closed;
  }

  close(): void {
    try {
      this.ws.close(1000, "done");
    } catch {
      // ignore
    }
  }
}

export async function openDevice(token: string): Promise<SocketClient> {
  const response = await SELF.fetch(`${ORIGIN}/ws/device`, {
    headers: { Upgrade: "websocket", Authorization: `Bearer ${token}`, "CF-Connecting-IP": nextIp() },
  });
  if (response.status !== 101 || !response.webSocket) {
    throw new Error(`device upgrade failed: ${response.status} ${await response.text()}`);
  }
  return new SocketClient(response.webSocket);
}

export async function openControl(cookie: string, origin: string = ORIGIN): Promise<SocketClient> {
  const response = await SELF.fetch(`${ORIGIN}/ws/control`, {
    headers: { Upgrade: "websocket", Cookie: cookie, Origin: origin, "CF-Connecting-IP": nextIp() },
  });
  if (response.status !== 101 || !response.webSocket) {
    throw new Error(`control upgrade failed: ${response.status} ${await response.text()}`);
  }
  return new SocketClient(response.webSocket);
}

/** Full pairing flow: phone requests a code, the control room claims it, the phone polls its token. */
export async function pairCamera(cookie: string, name: string, slot: number) {
  const ip = nextIp();
  const start = await api("/api/pair/start", { body: { deviceName: "Test phone", model: "Pixel Test", appVersion: "1.0.0" }, ip, origin: null });
  if (start.status !== 200) throw new Error(`pair start failed ${start.status}`);
  const pairing = (await start.json()) as { pairingId: string; code: string; pollToken: string };
  const claim = await api("/api/cameras/claim", { body: { code: pairing.code, name, slot }, cookie });
  if (claim.status !== 201) throw new Error(`claim failed ${claim.status} ${await claim.text()}`);
  const claimed = (await claim.json()) as { camera: { id: string } };
  const poll = await api("/api/pair/poll", {
    body: { pairingId: pairing.pairingId },
    headers: { Authorization: `Bearer ${pairing.pollToken}` },
    ip,
    origin: null,
  });
  const polled = (await poll.json()) as { status: string; deviceToken: string; cameraId: string };
  if (polled.status !== "paired") throw new Error(`poll status ${polled.status}`);
  return { cameraId: claimed.camera.id, deviceToken: polled.deviceToken, pairing };
}

export function uuid(): string {
  return crypto.randomUUID();
}
