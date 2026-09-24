import { DurableObject } from "cloudflare:workers";
import type { Env } from "./env";
import { boolVar, intVar, listVar, streamApiConfigured } from "./env";
import { Db, parseJson } from "./db";
import type { CameraRow, CommandRow, EventRow, PairingRow } from "./db";
import {
  HttpError,
  SESSION_COOKIE,
  bearerToken,
  clearSessionCookie,
  clientIp,
  errorResponse,
  isWebSocketUpgrade,
  json,
  parseCookies,
  readJson,
  sessionCookie,
} from "./lib/http";
import { generatePairingCode, randomId, randomToken, secretsEqual, sha256Hex } from "./lib/crypto";
import {
  COMMAND_TIMEOUT_MS,
  COMMAND_TTL_MS,
  MAX_MESSAGE_BYTES,
  PROTOCOL_VERSION,
  formatPairingCode,
  isRecord,
  isValidPairingCode,
  normalizePairingCode,
  sanitizeCapabilities,
  sanitizeState,
  sanitizeTelemetry,
  validateAck,
  validateCommandRequest,
} from "./shared/protocol";
import type {
  CameraStreamingConfig,
  CloudflareIngestState,
  CommandName,
  CommandStatus,
  DeviceCapabilities,
  DeviceCommand,
  DeviceState,
  ErrorInfo,
  Telemetry,
} from "./shared/protocol";
import {
  StreamApi,
  StreamApiError,
  buildRtmpsUrl,
  buildSrtUrl,
  extractCustomerCode,
  playbackUrls,
} from "./cloudflare/stream";
import { mapLiveInputStatus, parseLiveWebhook, rawLiveInputStatus } from "./cloudflare/liveStatus";
import { buildStreamingConfig, checkCommandSupported, isErrorInfo, sanitizeName, streamDefaults } from "./logic";

export const APP_VERSION = "1.0.0";

const MAX_SLOTS = 16;
const HEARTBEAT_INTERVAL_MS = 15_000;
const HEARTBEAT_TIMEOUT_MS = 50_000;
const MAINTENANCE_INTERVAL_MS = 5 * 60_000;
const TELEMETRY_PERSIST_MS = 30_000;
const CONFIG_CACHE_MS = 60_000;
const WATCHDOG_COOLDOWN_MS = 120_000;
const MAX_EVENTS = 1000;
const TEN_MINUTES = 10 * 60_000;

type DeviceAttachment = {
  role: "device";
  cameraId: string;
  connId: string;
  connectedAt: number;
  lastSeen: number;
};

type ControlAttachment = {
  role: "control";
  sessionHash: string;
  operator: string;
  connId: string;
  connectedAt: number;
  expiresAt: number;
};

type Attachment = DeviceAttachment | ControlAttachment;

interface Bucket {
  tokens: number;
  last: number;
  violations: number;
}

export interface CameraView {
  id: string;
  slot: number;
  name: string;
  online: boolean;
  activated: boolean;
  lastSeenAt: number | null;
  device: { model: string | null; appVersion: string | null; osVersion: string | null };
  capabilities: DeviceCapabilities | null;
  state: DeviceState | null;
  telemetry: Telemetry | null;
  cloudflare: {
    configured: boolean;
    liveInputId: string | null;
    state: CloudflareIngestState;
    status: string | null;
    statusAt: number | null;
    error: string | null;
  };
  playback: { iframeUrl: string; hlsUrl: string } | null;
}

export class StudioDurableObject extends DurableObject<Env> {
  private readonly db: Db;
  private readonly telemetry = new Map<string, Telemetry>();
  private readonly telemetryPersistedAt = new Map<string, number>();
  private readonly buckets = new Map<string, Bucket>();
  private readonly configCache = new Map<string, { config: CameraStreamingConfig; at: number }>();
  private readonly mismatch = new Map<string, { count: number; lastAction: number }>();
  private lastCloudflarePoll = 0;
  private lastMaintenance = 0;

  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    this.db = new Db(ctx.storage.sql);
    ctx.blockConcurrencyWhile(async () => {
      this.db.migrate();
    });
  }

  // -------------------------------------------------------------------------
  // HTTP routing
  // -------------------------------------------------------------------------

  async fetch(request: Request): Promise<Response> {
    try {
      return await this.route(request);
    } catch (err) {
      if (err instanceof HttpError) return errorResponse(err);
      console.error("Unhandled error", (err as Error).stack ?? String(err));
      return errorResponse(new HttpError(500, "internal_error", "Errore interno del server"));
    }
  }

  private async route(request: Request): Promise<Response> {
    const url = new URL(request.url);
    const path = url.pathname.replace(/\/+$/, "") || "/";
    const method = request.method.toUpperCase();

    if (path === "/ws/device") return this.acceptDevice(request);
    if (path === "/ws/control") return this.acceptControl(request);

    if (path === "/api/auth/login" && method === "POST") return this.login(request);
    if (path === "/api/auth/logout" && method === "POST") return this.logout(request);
    if (path === "/api/auth/me" && method === "GET") return this.me(request);
    if (path === "/api/config" && method === "GET") {
      await this.requireSession(request);
      return json({ ok: true, config: this.publicConfig() });
    }
    if (path === "/api/pair/start" && method === "POST") return this.pairStart(request);
    if (path === "/api/pair/poll" && method === "POST") return this.pairPoll(request);
    if (path === "/api/webhooks/stream" && method === "POST") return this.streamWebhook(request);
    if (path === "/api/events" && method === "GET") return this.listEvents(request, url);
    if (path === "/api/cameras" && method === "GET") {
      await this.requireSession(request);
      return json({ ok: true, cameras: this.db.cameras().map((c) => this.cameraView(c)) });
    }
    if (path === "/api/cameras/claim" && method === "POST") return this.claimCamera(request);

    const cameraMatch = /^\/api\/cameras\/([A-Za-z0-9_-]{8,64})(\/playback|\/live-input)?$/.exec(path);
    if (cameraMatch) {
      const [, cameraId, sub] = cameraMatch;
      if (!sub && method === "PATCH") return this.updateCamera(request, cameraId);
      if (!sub && method === "DELETE") return this.revokeCamera(request, cameraId);
      if (sub === "/playback" && method === "GET") return this.playback(request, cameraId);
      if (sub === "/live-input" && method === "POST") return this.liveInputAction(request, cameraId);
    }
    throw new HttpError(404, "not_found", "Endpoint non trovato");
  }

  // -------------------------------------------------------------------------
  // Control room authentication
  // -------------------------------------------------------------------------

  private checkOrigin(request: Request): void {
    const origin = request.headers.get("Origin");
    const self = new URL(request.url).origin;
    const allowed = new Set([self, ...listVar(this.env.ALLOWED_ORIGINS)]);
    if (!origin || !allowed.has(origin)) {
      throw new HttpError(403, "bad_origin", "Origine della richiesta non consentita");
    }
  }

  private async sessionFromRequest(request: Request): Promise<{ hash: string; operator: string; expiresAt: number } | null> {
    const token = parseCookies(request.headers.get("Cookie")).get(SESSION_COOKIE);
    if (!token || token.length < 20 || token.length > 128) return null;
    const hash = await sha256Hex(token);
    const row = this.db.first<{ operator: string; expires_at: number }>(
      "SELECT operator, expires_at FROM sessions WHERE token_hash = ? AND expires_at > ?",
      hash,
      Date.now(),
    );
    return row ? { hash, operator: row.operator, expiresAt: row.expires_at } : null;
  }

  private async requireSession(request: Request, mutating = false) {
    if (mutating) this.checkOrigin(request);
    const session = await this.sessionFromRequest(request);
    if (!session) throw new HttpError(401, "unauthorized", "Accesso alla regia richiesto");
    return session;
  }

  private async login(request: Request): Promise<Response> {
    this.checkOrigin(request);
    const now = Date.now();
    const ip = clientIp(request);
    if (!this.db.hit(`login:ip:${ip}`, 10, TEN_MINUTES, now) || !this.db.hit("login:global", 200, TEN_MINUTES, now)) {
      throw new HttpError(429, "rate_limited", "Troppi tentativi di accesso, riprova tra qualche minuto", {
        "Retry-After": "600",
      });
    }
    const configured = this.env.CONTROL_ROOM_PASSWORD;
    if (!configured || configured.length < 12) {
      throw new HttpError(503, "not_configured", "CONTROL_ROOM_PASSWORD non configurata (minimo 12 caratteri)");
    }
    const body = await readJson(request);
    const password = typeof body.password === "string" ? body.password : "";
    const operator = sanitizeName(body.operator ?? "Regia", 32) ?? "Regia";
    if (!(await secretsEqual(password, configured))) {
      this.logEvent(null, "warning", "auth", `Accesso regia fallito da ${ip}`);
      throw new HttpError(401, "invalid_credentials", "Password errata");
    }
    const token = randomToken(32);
    const ttlMs = intVar(this.env.SESSION_TTL_HOURS, 12, 1, 72) * 3600_000;
    const expiresAt = now + ttlMs;
    this.db.run(
      "INSERT INTO sessions (token_hash, operator, created_at, expires_at) VALUES (?, ?, ?, ?)",
      await sha256Hex(token),
      operator,
      now,
      expiresAt,
    );
    this.logEvent(null, "info", "auth", `Accesso regia: ${operator}`);
    await this.ensureAlarm(MAINTENANCE_INTERVAL_MS);
    const secure = new URL(request.url).protocol === "https:";
    return json({ ok: true, operator, expiresAt }, 200, {
      "Set-Cookie": sessionCookie(token, Math.floor(ttlMs / 1000), secure),
    });
  }

  private async logout(request: Request): Promise<Response> {
    this.checkOrigin(request);
    const session = await this.sessionFromRequest(request);
    if (session) {
      this.db.run("DELETE FROM sessions WHERE token_hash = ?", session.hash);
      for (const ws of this.ctx.getWebSockets("control")) {
        const att = ws.deserializeAttachment() as Attachment | null;
        if (att?.role === "control" && att.sessionHash === session.hash) this.closeSocket(ws, 4003, "logout");
      }
    }
    const secure = new URL(request.url).protocol === "https:";
    return json({ ok: true }, 200, { "Set-Cookie": clearSessionCookie(secure) });
  }

  private async me(request: Request): Promise<Response> {
    const session = await this.sessionFromRequest(request);
    return json({
      ok: true,
      authenticated: Boolean(session),
      operator: session?.operator ?? null,
      expiresAt: session?.expiresAt ?? null,
      loginConfigured: Boolean(this.env.CONTROL_ROOM_PASSWORD && this.env.CONTROL_ROOM_PASSWORD.length >= 12),
    });
  }

  private publicConfig() {
    return {
      appName: this.env.APP_NAME ?? "PeopleCare Remote Camera",
      version: APP_VERSION,
      protocol: PROTOCOL_VERSION,
      streamConfigured: streamApiConfigured(this.env),
      webhookConfigured: Boolean(this.env.STREAM_WEBHOOK_SECRET),
      customerCodeKnown: Boolean(this.customerCode()),
      watchdog: boolVar(this.env.CF_WATCHDOG, true),
      maxSlots: MAX_SLOTS,
    };
  }

  // -------------------------------------------------------------------------
  // Pairing
  // -------------------------------------------------------------------------

  private async pairStart(request: Request): Promise<Response> {
    const now = Date.now();
    const ip = clientIp(request);
    if (!this.db.hit(`pair:ip:${ip}`, 10, TEN_MINUTES, now)) {
      throw new HttpError(429, "rate_limited", "Troppe richieste di associazione", { "Retry-After": "600" });
    }
    const active = this.db.first<{ n: number }>(
      "SELECT COUNT(*) AS n FROM pairings WHERE expires_at > ? AND claimed_at IS NULL",
      now,
    );
    if ((active?.n ?? 0) >= 50) throw new HttpError(429, "too_many_pairings", "Troppe associazioni in corso");
    const body = await readJson(request, 4096);
    const deviceName = sanitizeName(body.deviceName, 64) ?? "Android";
    const model = sanitizeName(body.model, 64);
    const appVersion = sanitizeName(body.appVersion, 32);

    let code = generatePairingCode();
    let codeHash = await sha256Hex(code);
    for (let i = 0; i < 5 && this.db.first("SELECT 1 AS x FROM pairings WHERE code_hash = ?", codeHash); i++) {
      code = generatePairingCode();
      codeHash = await sha256Hex(code);
    }
    const pairingId = randomId("pair", 12);
    const pollToken = randomToken(32);
    const ttlMs = intVar(this.env.PAIRING_TTL_MINUTES, 10, 2, 60) * 60_000;
    const expiresAt = now + ttlMs;
    this.db.run(
      `INSERT INTO pairings (id, code_hash, poll_hash, device_name, model, app_version, created_at, expires_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
      pairingId,
      codeHash,
      await sha256Hex(pollToken),
      deviceName,
      model,
      appVersion,
      now,
      expiresAt,
    );
    this.logEvent(null, "info", "pairing", `Nuova richiesta di associazione da "${deviceName}"${model ? ` (${model})` : ""}`);
    await this.ensureAlarm(ttlMs + 1000);
    return json({
      ok: true,
      pairingId,
      code: formatPairingCode(code),
      pollToken,
      expiresAt,
      pollIntervalMs: 3000,
    });
  }

  private async pairPoll(request: Request): Promise<Response> {
    const now = Date.now();
    const token = bearerToken(request);
    const body = await readJson(request, 1024);
    const pairingId = typeof body.pairingId === "string" ? body.pairingId : "";
    if (!token || !/^pair_[0-9a-f]{24}$/.test(pairingId)) {
      throw new HttpError(400, "bad_request", "pairingId e token richiesti");
    }
    if (!this.db.hit(`poll:${pairingId}`, 400, TEN_MINUTES, now)) {
      throw new HttpError(429, "rate_limited", "Polling troppo frequente", { "Retry-After": "30" });
    }
    const pairing = this.db.first<PairingRow>("SELECT * FROM pairings WHERE id = ?", pairingId);
    if (!pairing || !(await secretsEqual(await sha256Hex(token), pairing.poll_hash))) {
      throw new HttpError(404, "unknown_pairing", "Associazione non trovata");
    }
    if (!pairing.claimed_at) {
      if (pairing.expires_at <= now) return json({ ok: true, status: "expired" });
      return json({ ok: true, status: "pending", expiresAt: pairing.expires_at });
    }
    const camera = pairing.camera_id ? this.db.camera(pairing.camera_id) : null;
    if (!camera) return json({ ok: true, status: "expired" });
    if (camera.activated_at) return json({ ok: true, status: "consumed" });
    // A fresh device token is issued on every poll until the phone connects
    // with it: a lost response never leaves the camera unusable, and only the
    // last issued token is valid.
    const deviceToken = randomToken(32);
    this.db.run("UPDATE cameras SET device_token_hash = ? WHERE id = ?", await sha256Hex(deviceToken), camera.id);
    this.db.run("UPDATE pairings SET issued_at = ? WHERE id = ?", now, pairing.id);
    return json({
      ok: true,
      status: "paired",
      cameraId: camera.id,
      cameraName: camera.name,
      slot: camera.slot,
      deviceToken,
    });
  }

  private async claimCamera(request: Request): Promise<Response> {
    const session = await this.requireSession(request, true);
    const now = Date.now();
    if (!this.db.hit(`claim:${session.hash}`, 20, TEN_MINUTES, now)) {
      throw new HttpError(429, "rate_limited", "Troppi tentativi di associazione", { "Retry-After": "600" });
    }
    const body = await readJson(request, 2048);
    const code = normalizePairingCode(typeof body.code === "string" ? body.code : "");
    const name = sanitizeName(body.name, 48);
    const slot = typeof body.slot === "number" && Number.isInteger(body.slot) ? body.slot : NaN;
    if (!isValidPairingCode(code)) throw new HttpError(400, "invalid_code", "Codice di associazione non valido");
    if (!name) throw new HttpError(400, "invalid_name", "Nome camera obbligatorio (max 48 caratteri)");
    if (!(slot >= 1 && slot <= MAX_SLOTS)) throw new HttpError(400, "invalid_slot", `Slot deve essere tra 1 e ${MAX_SLOTS}`);
    if (this.db.first("SELECT 1 AS x FROM cameras WHERE slot = ?", slot)) {
      throw new HttpError(409, "slot_taken", `Lo slot CAM ${String(slot).padStart(2, "0")} è già occupato`);
    }
    const pairing = this.db.first<PairingRow>(
      "SELECT * FROM pairings WHERE code_hash = ? AND expires_at > ? AND claimed_at IS NULL",
      await sha256Hex(code),
      now,
    );
    if (!pairing) {
      this.logEvent(null, "warning", "pairing", `Codice di associazione non valido inserito da ${session.operator}`);
      throw new HttpError(404, "unknown_code", "Codice non trovato o scaduto: genera un nuovo codice sul telefono");
    }
    const cameraId = randomId("cam", 8);
    this.db.run(
      `INSERT INTO cameras (id, slot, name, created_at, device_model, app_version)
       VALUES (?, ?, ?, ?, ?, ?)`,
      cameraId,
      slot,
      name,
      now,
      pairing.model,
      pairing.app_version,
    );
    this.db.run("UPDATE pairings SET claimed_at = ?, camera_id = ? WHERE id = ?", now, cameraId, pairing.id);
    this.logEvent(cameraId, "info", "pairing", `Camera "${name}" associata da ${session.operator}`);

    let warning: string | null = null;
    const api = this.streamApi();
    if (api) {
      try {
        await this.createLiveInput(api, cameraId, name);
      } catch (err) {
        warning = `Live input Cloudflare non creato: ${(err as Error).message}`;
        this.logEvent(cameraId, "error", "cloudflare", warning);
      }
    } else {
      warning = "Cloudflare Stream non configurato: la camera non potrà trasmettere finché non imposti i secret";
    }
    const camera = this.db.camera(cameraId);
    if (!camera) throw new HttpError(500, "internal_error", "Camera non salvata");
    this.broadcastCamera(camera);
    return json({ ok: true, camera: this.cameraView(camera), warning }, 201);
  }

  // -------------------------------------------------------------------------
  // Camera management
  // -------------------------------------------------------------------------

  private async updateCamera(request: Request, cameraId: string): Promise<Response> {
    const session = await this.requireSession(request, true);
    const camera = this.requireCamera(cameraId);
    const body = await readJson(request, 2048);
    let name = camera.name;
    let slot = camera.slot;
    if (body.name !== undefined) {
      const cleaned = sanitizeName(body.name, 48);
      if (!cleaned) throw new HttpError(400, "invalid_name", "Nome non valido");
      name = cleaned;
    }
    if (body.slot !== undefined) {
      const value = body.slot;
      if (typeof value !== "number" || !Number.isInteger(value) || value < 1 || value > MAX_SLOTS) {
        throw new HttpError(400, "invalid_slot", "Slot non valido");
      }
      if (value !== camera.slot && this.db.first("SELECT 1 AS x FROM cameras WHERE slot = ? AND id != ?", value, cameraId)) {
        throw new HttpError(409, "slot_taken", "Slot già occupato");
      }
      slot = value;
    }
    this.db.run("UPDATE cameras SET name = ?, slot = ? WHERE id = ?", name, slot, cameraId);
    this.configCache.delete(cameraId);
    this.logEvent(cameraId, "info", "regia", `Camera rinominata in "${name}" (slot ${slot}) da ${session.operator}`);
    const device = this.deviceSocket(cameraId);
    if (device) this.send(device, { v: PROTOCOL_VERSION, type: "camera_info", cameraName: name, slot });
    const updated = this.requireCamera(cameraId);
    this.broadcastCamera(updated);
    return json({ ok: true, camera: this.cameraView(updated) });
  }

  private async revokeCamera(request: Request, cameraId: string): Promise<Response> {
    const session = await this.requireSession(request, true);
    const camera = this.requireCamera(cameraId);
    const device = this.deviceSocket(cameraId);
    if (device) {
      this.send(device, { v: PROTOCOL_VERSION, type: "revoked" });
      this.closeSocket(device, 4001, "revoked");
    }
    let cloudflareAction = "none";
    const api = this.streamApi();
    if (api && camera.live_input_id) {
      const action = (this.env.REVOKE_ACTION ?? "rotate").toLowerCase();
      try {
        if (action === "delete") {
          await api.deleteLiveInput(camera.live_input_id);
          cloudflareAction = "deleted";
        } else if (action === "disable") {
          await api.setEnabled(camera.live_input_id, false);
          cloudflareAction = "disabled";
        } else if (action === "rotate") {
          await api.rotateKeys(camera.live_input_id);
          cloudflareAction = "keys_rotated";
        }
      } catch (err) {
        cloudflareAction = `failed: ${(err as Error).message}`;
      }
    }
    this.db.run("DELETE FROM cameras WHERE id = ?", cameraId);
    this.db.run("DELETE FROM pairings WHERE camera_id = ?", cameraId);
    this.db.run(
      "UPDATE commands SET status = 'failed', error_json = ?, updated_at = ? WHERE camera_id = ? AND status IN ('sent','received')",
      JSON.stringify({ code: "camera_revoked", message: "Camera revocata" }),
      Date.now(),
      cameraId,
    );
    this.telemetry.delete(cameraId);
    this.configCache.delete(cameraId);
    this.logEvent(
      cameraId,
      "warning",
      "regia",
      `Dispositivo "${camera.name}" revocato da ${session.operator} (live input: ${cloudflareAction})`,
    );
    this.broadcastControl({ v: PROTOCOL_VERSION, type: "camera_removed", cameraId });
    return json({ ok: true, cloudflareAction });
  }

  private async playback(request: Request, cameraId: string): Promise<Response> {
    const session = await this.requireSession(request);
    const camera = this.requireCamera(cameraId);
    const api = this.streamApi();
    if (!api) throw new HttpError(409, "cloudflare_not_configured", "Cloudflare Stream non configurato");
    if (!camera.live_input_id) throw new HttpError(409, "no_live_input", "Nessun live input per questa camera");
    const input = await this.callStream(() => api.getLiveInput(camera.live_input_id as string));
    this.logEvent(cameraId, "info", "regia", `Credenziali di playback OBS visualizzate da ${session.operator}`);
    const srt = input.srtPlayback;
    const rtmps = input.rtmpsPlayback;
    return json({
      ok: true,
      liveInputId: camera.live_input_id,
      player: playbackUrls(this.customerCode(), camera.live_input_id),
      srt: srt?.url
        ? {
            url: srt.url,
            streamId: srt.streamId ?? null,
            passphrase: srt.passphrase ?? null,
            obsUrl: buildSrtUrl(srt.url, srt.streamId, srt.passphrase),
          }
        : null,
      rtmps: rtmps?.url
        ? { url: rtmps.url, streamKey: rtmps.streamKey ?? null, obsUrl: buildRtmpsUrl(rtmps.url, rtmps.streamKey) }
        : null,
    });
  }

  private async liveInputAction(request: Request, cameraId: string): Promise<Response> {
    const session = await this.requireSession(request, true);
    const camera = this.requireCamera(cameraId);
    const api = this.streamApi();
    if (!api) throw new HttpError(409, "cloudflare_not_configured", "Cloudflare Stream non configurato");
    const body = await readJson(request, 1024);
    const action = body.action;
    let message: string;
    if (action === "create") {
      if (camera.live_input_id) throw new HttpError(409, "exists", "Live input già presente");
      await this.createLiveInput(api, camera.id, camera.name);
      message = "Live input creato";
    } else {
      if (!camera.live_input_id) throw new HttpError(409, "no_live_input", "Nessun live input per questa camera");
      const uid = camera.live_input_id;
      if (action === "enable" || action === "disable") {
        const input = await this.callStream(() => api.setEnabled(uid, action === "enable"));
        this.applyLiveInputStatus(camera.id, input.enabled === false ? "disabled" : rawLiveInputStatus(input.status), "api");
        message = action === "enable" ? "Live input abilitato" : "Live input disabilitato";
      } else if (action === "rotate") {
        await this.callStream(() => api.rotateKeys(uid));
        message = "Chiavi del live input ruotate";
        const device = this.deviceSocket(camera.id);
        this.configCache.delete(camera.id);
        if (device) void this.sendConfig(device, camera.id);
      } else if (action === "refresh") {
        const input = await this.callStream(() => api.getLiveInput(uid));
        this.applyLiveInputStatus(camera.id, input.enabled === false ? "disabled" : rawLiveInputStatus(input.status), "api");
        message = "Stato aggiornato";
      } else {
        throw new HttpError(400, "invalid_action", "Azione non valida");
      }
    }
    this.configCache.delete(camera.id);
    this.logEvent(camera.id, "info", "cloudflare", `${message} (${session.operator})`);
    const updated = this.requireCamera(camera.id);
    this.broadcastCamera(updated);
    return json({ ok: true, message, camera: this.cameraView(updated) });
  }

  private async listEvents(request: Request, url: URL): Promise<Response> {
    await this.requireSession(request);
    const limit = intVar(url.searchParams.get("limit") ?? undefined, 100, 1, 500);
    const cameraId = url.searchParams.get("cameraId");
    const rows = cameraId
      ? this.db.all<EventRow>("SELECT * FROM events WHERE camera_id = ? ORDER BY id DESC LIMIT ?", cameraId, limit)
      : this.db.all<EventRow>("SELECT * FROM events ORDER BY id DESC LIMIT ?", limit);
    return json({ ok: true, events: rows.reverse().map(eventView) });
  }

  private requireCamera(cameraId: string): CameraRow {
    const camera = this.db.camera(cameraId);
    if (!camera) throw new HttpError(404, "unknown_camera", "Camera non trovata");
    return camera;
  }

  // -------------------------------------------------------------------------
  // Cloudflare Stream
  // -------------------------------------------------------------------------

  private streamApi(): StreamApi | null {
    if (!streamApiConfigured(this.env)) return null;
    return new StreamApi(
      this.env.CLOUDFLARE_ACCOUNT_ID as string,
      this.env.CLOUDFLARE_API_TOKEN as string,
      (input, init) => fetch(input, init),
      this.env.CLOUDFLARE_API_BASE || undefined,
    );
  }

  private async callStream<T>(fn: () => Promise<T>): Promise<T> {
    try {
      return await fn();
    } catch (err) {
      if (err instanceof StreamApiError) {
        throw new HttpError(502, "cloudflare_error", err.message);
      }
      throw err;
    }
  }

  private async createLiveInput(api: StreamApi, cameraId: string, name: string): Promise<void> {
    const mode = (this.env.STREAM_RECORDING_MODE ?? "automatic").toLowerCase() === "off" ? "off" : "automatic";
    const days = intVar(this.env.STREAM_DELETE_RECORDING_AFTER_DAYS, 30, 0, 1096);
    const input = await api.createLiveInput({
      name,
      cameraId,
      recordingMode: mode,
      deleteRecordingAfterDays: days >= 30 ? days : null,
      preferLowLatency: boolVar(this.env.STREAM_PREFER_LOW_LATENCY, false) && mode === "automatic",
      allowedOrigins: listVar(this.env.STREAM_ALLOWED_ORIGINS),
    });
    this.db.run(
      "UPDATE cameras SET live_input_id = ?, cf_state = 'offline', cf_status = NULL, cf_status_at = ? WHERE id = ?",
      input.uid,
      Date.now(),
      cameraId,
    );
    this.logEvent(cameraId, "info", "cloudflare", `Live input Cloudflare creato (${input.uid})`);
  }

  private customerCode(): string | null {
    const configured = this.env.CLOUDFLARE_STREAM_CUSTOMER_CODE?.trim();
    if (configured) return configured.replace(/^customer-/, "").replace(/\.cloudflarestream\.com.*$/, "");
    return this.db.getMeta("customer_code");
  }

  private async resolveCustomerCode(api: StreamApi, liveInputId: string): Promise<void> {
    if (this.customerCode()) return;
    try {
      const videos = await api.listVideos(liveInputId);
      for (const video of videos) {
        const code = extractCustomerCode(video.preview, video.thumbnail, video.playback?.hls);
        if (code) {
          this.db.setMeta("customer_code", code);
          return;
        }
      }
    } catch {
      // Best effort only: the player URL appears as soon as a video exists.
    }
  }

  private applyLiveInputStatus(
    cameraId: string,
    raw: string | null,
    source: "poll" | "webhook" | "api",
    error: string | null = null,
  ): CloudflareIngestState {
    const state: CloudflareIngestState = raw === "disabled" ? "disabled" : mapLiveInputStatus(raw);
    const camera = this.db.camera(cameraId);
    if (!camera) return state;
    const changed = camera.cf_state !== state || camera.cf_status !== raw || (error ?? null) !== camera.cf_error;
    this.db.run(
      "UPDATE cameras SET cf_status = ?, cf_state = ?, cf_status_at = ?, cf_error = ? WHERE id = ?",
      raw,
      state,
      Date.now(),
      error,
      cameraId,
    );
    if (changed) {
      const level = state === "error" ? "error" : state === "live" ? "info" : "warning";
      this.logEvent(cameraId, level, "cloudflare", `Ingest Cloudflare: ${state}${raw ? ` (${raw})` : ""}${error ? ` – ${error}` : ""} [${source}]`);
      const updated = this.db.camera(cameraId);
      if (updated) this.broadcastCamera(updated);
      const device = this.deviceSocket(cameraId);
      if (device) {
        this.send(device, {
          v: PROTOCOL_VERSION,
          type: "cloudflare_status",
          state,
          status: raw,
          error,
          at: Date.now(),
        });
      }
    }
    return state;
  }

  private async streamWebhook(request: Request): Promise<Response> {
    const secret = this.env.STREAM_WEBHOOK_SECRET;
    if (!secret) throw new HttpError(404, "not_found", "Webhook non configurato");
    const provided = request.headers.get("cf-webhook-auth") ?? "";
    if (!(await secretsEqual(provided, secret))) {
      throw new HttpError(401, "unauthorized", "Firma webhook non valida");
    }
    const event = parseLiveWebhook(await readJson(request, 16 * 1024));
    if (!event) return json({ ok: true, ignored: true });
    const camera = this.db.cameraByLiveInput(event.inputId);
    if (!camera) return json({ ok: true, ignored: true });
    const error = event.errorCode ? `${event.errorCode}${event.errorMessage ? `: ${event.errorMessage}` : ""}` : null;
    this.applyLiveInputStatus(camera.id, event.eventType, "webhook", error);
    return json({ ok: true });
  }

  private async fetchStreamingConfig(cameraId: string): Promise<CameraStreamingConfig | ErrorInfo> {
    const cached = this.configCache.get(cameraId);
    if (cached && Date.now() - cached.at < CONFIG_CACHE_MS) return cached.config;
    const api = this.streamApi();
    if (!api) {
      return { code: "cloudflare_not_configured", message: "Cloudflare Stream non configurato sul server" };
    }
    let camera = this.db.camera(cameraId);
    if (!camera) return { code: "unknown_camera", message: "Camera non trovata" };
    try {
      if (!camera.live_input_id) {
        await this.createLiveInput(api, camera.id, camera.name);
        camera = this.db.camera(cameraId);
        if (!camera?.live_input_id) return { code: "live_input_missing", message: "Live input non disponibile" };
      }
      const input = await api.getLiveInput(camera.live_input_id);
      const config = buildStreamingConfig({ id: camera.id, name: camera.name }, input, streamDefaults(this.env), Date.now());
      if (!isErrorInfo(config)) this.configCache.set(cameraId, { config, at: Date.now() });
      return config;
    } catch (err) {
      const message = err instanceof StreamApiError ? err.message : (err as Error).message;
      this.logEvent(cameraId, "error", "cloudflare", `Recupero configurazione fallito: ${message}`);
      return { code: "cloudflare_error", message: "Errore Cloudflare nel recupero del live input" };
    }
  }

  private async sendConfig(ws: WebSocket, cameraId: string): Promise<void> {
    const config = await this.fetchStreamingConfig(cameraId);
    if (isErrorInfo(config)) {
      this.send(ws, { v: PROTOCOL_VERSION, type: "config", config: null, error: config });
    } else {
      this.send(ws, { v: PROTOCOL_VERSION, type: "config", config, error: null });
    }
  }

  // -------------------------------------------------------------------------
  // WebSockets
  // -------------------------------------------------------------------------

  private async acceptDevice(request: Request): Promise<Response> {
    // The token is checked before the upgrade: a plain GET lets the phone tell
    // a revoked token (401) from a network problem (426 = token valid).
    const token = bearerToken(request);
    if (!token) throw new HttpError(401, "unauthorized", "Token dispositivo mancante");
    const camera = this.db.cameraByTokenHash(await sha256Hex(token));
    if (!camera) throw new HttpError(401, "unauthorized", "Token dispositivo non valido o revocato");
    if (!isWebSocketUpgrade(request)) throw new HttpError(426, "upgrade_required", "WebSocket richiesto");
    const now = Date.now();
    for (const old of this.ctx.getWebSockets(`cam:${camera.id}`)) {
      this.closeSocket(old, 4002, "replaced");
    }
    const pair = new WebSocketPair();
    const [client, server] = Object.values(pair);
    const connId = randomId("conn", 8);
    this.ctx.acceptWebSocket(server, ["device", `cam:${camera.id}`]);
    const attachment: DeviceAttachment = { role: "device", cameraId: camera.id, connId, connectedAt: now, lastSeen: now };
    server.serializeAttachment(attachment);
    if (!camera.activated_at) {
      this.db.run("UPDATE cameras SET activated_at = ? WHERE id = ?", now, camera.id);
      this.db.run("DELETE FROM pairings WHERE camera_id = ?", camera.id);
    }
    this.db.run("UPDATE cameras SET last_seen_at = ? WHERE id = ?", now, camera.id);
    this.send(server, {
      v: PROTOCOL_VERSION,
      type: "welcome",
      cameraId: camera.id,
      cameraName: camera.name,
      slot: camera.slot,
      connId,
      serverTime: now,
      heartbeatIntervalMs: HEARTBEAT_INTERVAL_MS,
      cloudflare: {
        configured: streamApiConfigured(this.env),
        state: camera.cf_state ?? (streamApiConfigured(this.env) ? "unknown" : "unconfigured"),
      },
    });
    this.logEvent(camera.id, "info", "device", `Telefono connesso alla regia`);
    const updated = this.db.camera(camera.id);
    if (updated) this.broadcastCamera(updated);
    await this.ensureAlarm(60_000);
    return new Response(null, { status: 101, webSocket: client });
  }

  private async acceptControl(request: Request): Promise<Response> {
    if (!isWebSocketUpgrade(request)) throw new HttpError(426, "upgrade_required", "WebSocket richiesto");
    this.checkOrigin(request);
    const session = await this.sessionFromRequest(request);
    if (!session) throw new HttpError(401, "unauthorized", "Accesso alla regia richiesto");
    const pair = new WebSocketPair();
    const [client, server] = Object.values(pair);
    const connId = randomId("ctl", 8);
    this.ctx.acceptWebSocket(server, ["control"]);
    const attachment: ControlAttachment = {
      role: "control",
      sessionHash: session.hash,
      operator: session.operator,
      connId,
      connectedAt: Date.now(),
      expiresAt: session.expiresAt,
    };
    server.serializeAttachment(attachment);
    this.send(server, this.snapshot(session.operator));
    await this.ensureAlarm(MAINTENANCE_INTERVAL_MS);
    return new Response(null, { status: 101, webSocket: client });
  }

  private snapshot(operator: string) {
    const events = this.db.all<EventRow>("SELECT * FROM events ORDER BY id DESC LIMIT 100").reverse();
    const commands = this.db.all<CommandRow>(
      "SELECT * FROM commands WHERE updated_at > ? ORDER BY updated_at DESC LIMIT 50",
      Date.now() - TEN_MINUTES,
    );
    return {
      v: PROTOCOL_VERSION,
      type: "snapshot",
      serverTime: Date.now(),
      operator,
      config: this.publicConfig(),
      cameras: this.db.cameras().map((c) => this.cameraView(c)),
      events: events.map(eventView),
      commands: commands.map(commandView),
    };
  }

  async webSocketMessage(ws: WebSocket, message: string | ArrayBuffer): Promise<void> {
    const att = ws.deserializeAttachment() as Attachment | null;
    if (!att) {
      this.closeSocket(ws, 1011, "missing state");
      return;
    }
    if (typeof message !== "string") {
      this.closeSocket(ws, 1003, "text frames only");
      return;
    }
    if (message.length > MAX_MESSAGE_BYTES) {
      this.closeSocket(ws, 1009, "message too big");
      return;
    }
    if (!this.consumeToken(att)) {
      const bucket = this.buckets.get(att.connId);
      if (bucket && bucket.violations > 50) {
        this.closeSocket(ws, 1008, "rate limit");
      } else {
        this.send(ws, { v: PROTOCOL_VERSION, type: "error", code: "rate_limited", message: "Troppi messaggi" });
      }
      return;
    }
    let data: unknown;
    try {
      data = JSON.parse(message);
    } catch {
      this.send(ws, { v: PROTOCOL_VERSION, type: "error", code: "invalid_json", message: "JSON non valido" });
      return;
    }
    if (!isRecord(data) || data.v !== PROTOCOL_VERSION || typeof data.type !== "string") {
      this.send(ws, { v: PROTOCOL_VERSION, type: "error", code: "invalid_message", message: "Messaggio non valido" });
      return;
    }
    if (att.role === "device") {
      await this.onDeviceMessage(ws, att, data);
    } else {
      await this.onControlMessage(ws, att, data);
    }
  }

  async webSocketClose(ws: WebSocket, code: number, reason: string): Promise<void> {
    this.onSocketGone(ws, `chiusura ${code}${reason ? ` ${reason}` : ""}`);
  }

  async webSocketError(ws: WebSocket, error: unknown): Promise<void> {
    this.onSocketGone(ws, `errore ${(error as Error)?.message ?? "sconosciuto"}`);
  }

  private onSocketGone(ws: WebSocket, detail: string): void {
    const att = ws.deserializeAttachment() as Attachment | null;
    if (!att) return;
    this.buckets.delete(att.connId);
    if (att.role !== "device") return;
    const stillConnected = this.ctx
      .getWebSockets(`cam:${att.cameraId}`)
      .some((other) => other !== ws && other.readyState === WebSocket.READY_STATE_OPEN);
    if (stillConnected) return;
    const now = Date.now();
    this.db.run("UPDATE cameras SET last_seen_at = ? WHERE id = ?", now, att.cameraId);
    const failed = this.db.all<CommandRow>(
      "SELECT * FROM commands WHERE camera_id = ? AND status IN ('sent','received')",
      att.cameraId,
    );
    for (const row of failed) {
      this.finishCommand(row, "failed", null, { code: "camera_disconnected", message: "Telefono disconnesso prima dell'ACK" });
    }
    const camera = this.db.camera(att.cameraId);
    if (camera) {
      this.logEvent(camera.id, "warning", "device", `Telefono disconnesso dalla regia (${detail})`);
      this.broadcastCamera(camera, ws);
    }
  }

  private consumeToken(att: Attachment): boolean {
    const capacity = att.role === "device" ? 40 : 60;
    const refillPerSec = att.role === "device" ? 10 : 20;
    const now = Date.now();
    const bucket = this.buckets.get(att.connId) ?? { tokens: capacity, last: now, violations: 0 };
    bucket.tokens = Math.min(capacity, bucket.tokens + ((now - bucket.last) / 1000) * refillPerSec);
    bucket.last = now;
    this.buckets.set(att.connId, bucket);
    if (bucket.tokens < 1) {
      bucket.violations++;
      return false;
    }
    bucket.tokens -= 1;
    return true;
  }

  private async onDeviceMessage(ws: WebSocket, att: DeviceAttachment, data: Record<string, unknown>): Promise<void> {
    const now = Date.now();
    att.lastSeen = now;
    ws.serializeAttachment(att);
    const camera = this.db.camera(att.cameraId);
    if (!camera) {
      this.closeSocket(ws, 4001, "revoked");
      return;
    }
    switch (data.type) {
      case "ping":
        this.send(ws, { v: PROTOCOL_VERSION, type: "pong", t: typeof data.t === "number" ? data.t : null, serverTime: now });
        return;
      case "hello": {
        const caps = sanitizeCapabilities(data.capabilities);
        const state = sanitizeState(data.state);
        const device = isRecord(data.device) ? data.device : {};
        this.db.run(
          `UPDATE cameras SET capabilities_json = ?, state_json = ?, device_model = COALESCE(?, device_model),
             app_version = COALESCE(?, app_version), os_version = COALESCE(?, os_version), last_seen_at = ? WHERE id = ?`,
          caps ? JSON.stringify(caps) : camera.capabilities_json,
          state ? JSON.stringify(state) : camera.state_json,
          sanitizeName(device.model, 64),
          sanitizeName(device.appVersion, 32),
          sanitizeName(device.osVersion, 32),
          now,
          camera.id,
        );
        const updated = this.db.camera(camera.id);
        if (updated) this.broadcastCamera(updated);
        return;
      }
      case "state": {
        const state = sanitizeState(data.state);
        if (!state) return;
        const previous = parseJson<DeviceState>(camera.state_json);
        const caps = data.capabilities === undefined ? null : sanitizeCapabilities(data.capabilities);
        this.db.run(
          "UPDATE cameras SET state_json = ?, capabilities_json = COALESCE(?, capabilities_json) WHERE id = ?",
          JSON.stringify(state),
          caps ? JSON.stringify(caps) : null,
          camera.id,
        );
        if (previous?.streamStatus !== state.streamStatus) {
          const level = state.streamStatus === "error" ? "error" : state.streamStatus === "reconnecting" ? "warning" : "info";
          this.logEvent(camera.id, level, "device", `Stato stream: ${state.streamStatus}${state.lastError ? ` – ${state.lastError.message}` : ""}`);
          if (["connecting", "live", "reconnecting"].includes(state.streamStatus)) {
            await this.ensureAlarm(intVar(this.env.CF_POLL_INTERVAL_SECONDS, 20, 10, 300) * 1000);
          }
        }
        const updated = this.db.camera(camera.id);
        if (updated) this.broadcastCamera(updated);
        return;
      }
      case "telemetry": {
        const telemetry = sanitizeTelemetry(data.telemetry, now);
        if (!telemetry) return;
        this.telemetry.set(camera.id, telemetry);
        const persistedAt = this.telemetryPersistedAt.get(camera.id) ?? 0;
        if (now - persistedAt > TELEMETRY_PERSIST_MS) {
          this.db.run("UPDATE cameras SET telemetry_json = ?, last_seen_at = ? WHERE id = ?", JSON.stringify(telemetry), now, camera.id);
          this.telemetryPersistedAt.set(camera.id, now);
        }
        this.broadcastControl({ v: PROTOCOL_VERSION, type: "telemetry", cameraId: camera.id, telemetry });
        return;
      }
      case "ack": {
        const result = validateAck(data);
        if (!result.ok) {
          this.send(ws, { v: PROTOCOL_VERSION, type: "error", code: "invalid_ack", message: result.error });
          return;
        }
        const ack = result.value;
        const row = this.db.first<CommandRow>(
          "SELECT * FROM commands WHERE command_id = ? AND camera_id = ?",
          ack.commandId,
          camera.id,
        );
        if (!row) return;
        if (ack.stage === "received") {
          if (row.status === "sent") {
            this.db.run("UPDATE commands SET status = 'received', updated_at = ? WHERE command_id = ?", now, row.command_id);
            this.broadcastCommandStatus({ ...row, status: "received", updated_at: now });
          }
          return;
        }
        this.finishCommand(row, ack.ok ? "completed" : "failed", ack.result ?? null, ack.ok ? null : ack.error ?? null);
        return;
      }
      case "log": {
        const level = data.level === "error" || data.level === "warning" ? data.level : "info";
        const message = typeof data.message === "string" ? data.message.slice(0, 300) : "";
        if (message && this.db.hit(`devlog:${camera.id}`, 60, 60_000, now)) {
          this.logEvent(camera.id, level, "device", message);
        }
        return;
      }
      case "config_request":
        await this.sendConfig(ws, camera.id);
        return;
      default:
        this.send(ws, { v: PROTOCOL_VERSION, type: "error", code: "unknown_type", message: `Tipo sconosciuto: ${String(data.type)}` });
    }
  }

  private async onControlMessage(ws: WebSocket, att: ControlAttachment, data: Record<string, unknown>): Promise<void> {
    const now = Date.now();
    if (att.expiresAt <= now || !this.db.first("SELECT 1 AS x FROM sessions WHERE token_hash = ? AND expires_at > ?", att.sessionHash, now)) {
      this.send(ws, { v: PROTOCOL_VERSION, type: "error", code: "session_expired", message: "Sessione scaduta" });
      this.closeSocket(ws, 4003, "session expired");
      return;
    }
    switch (data.type) {
      case "ping":
        this.send(ws, { v: PROTOCOL_VERSION, type: "pong", t: typeof data.t === "number" ? data.t : null, serverTime: now });
        return;
      case "command": {
        const validated = validateCommandRequest(data, now);
        if (!validated.ok) {
          this.send(ws, {
            v: PROTOCOL_VERSION,
            type: "command_status",
            commandId: typeof data.commandId === "string" ? data.commandId.slice(0, 64) : null,
            cameraId: typeof data.cameraId === "string" ? data.cameraId.slice(0, 64) : null,
            command: typeof data.command === "string" ? data.command.slice(0, 32) : null,
            status: "rejected",
            error: { code: "invalid_command", message: validated.error },
            updatedAt: now,
          });
          return;
        }
        const request = validated.value;
        const outcome = this.dispatchCommand(request.cameraId, request.command, request.value, att.operator, request.commandId, request.issuedAt);
        if (!outcome.ok) {
          this.send(ws, {
            v: PROTOCOL_VERSION,
            type: "command_status",
            commandId: request.commandId,
            cameraId: request.cameraId,
            command: request.command,
            status: outcome.status,
            error: outcome.error,
            issuedBy: att.operator,
            updatedAt: now,
          });
        }
        await this.ensureAlarm(COMMAND_TIMEOUT_MS + 500);
        return;
      }
      default:
        this.send(ws, { v: PROTOCOL_VERSION, type: "error", code: "unknown_type", message: `Tipo sconosciuto: ${String(data.type)}` });
    }
  }

  /**
   * Forwards a validated command to the phone. The command is recorded before
   * it is sent: its id can never be accepted twice (anti replay), and its
   * outcome is only ever set by a real ACK from the phone or by a timeout.
   */
  private dispatchCommand(
    cameraId: string,
    command: CommandName,
    value: unknown,
    issuedBy: string,
    commandId: string,
    issuedAt: number,
  ): { ok: true } | { ok: false; status: CommandStatus; error: ErrorInfo } {
    const now = Date.now();
    if (this.db.first("SELECT 1 AS x FROM commands WHERE command_id = ?", commandId)) {
      return { ok: false, status: "rejected", error: { code: "duplicate_command", message: "Comando già ricevuto (replay rifiutato)" } };
    }
    const camera = this.db.camera(cameraId);
    if (!camera) return { ok: false, status: "rejected", error: { code: "unknown_camera", message: "Camera non trovata" } };
    const device = this.deviceSocket(cameraId);
    const valueJson = value === undefined || value === null ? null : JSON.stringify(value);
    if (!device) {
      const error = { code: "camera_offline", message: "Il telefono non è connesso alla regia" };
      this.db.run(
        `INSERT INTO commands (command_id, camera_id, command, value_json, issued_by, issued_at, status, error_json, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, 'failed', ?, ?)`,
        commandId,
        cameraId,
        command,
        valueJson,
        issuedBy,
        issuedAt,
        JSON.stringify(error),
        now,
      );
      return { ok: false, status: "failed", error };
    }
    const unsupported = checkCommandSupported(
      parseJson<DeviceCapabilities>(camera.capabilities_json),
      parseJson<DeviceState>(camera.state_json),
      command,
      value,
    );
    if (unsupported) {
      this.db.run(
        `INSERT INTO commands (command_id, camera_id, command, value_json, issued_by, issued_at, status, error_json, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, 'rejected', ?, ?)`,
        commandId,
        cameraId,
        command,
        valueJson,
        issuedBy,
        issuedAt,
        JSON.stringify(unsupported),
        now,
      );
      return { ok: false, status: "rejected", error: unsupported };
    }
    const seq = camera.cmd_seq + 1;
    this.db.run("UPDATE cameras SET cmd_seq = ? WHERE id = ?", seq, cameraId);
    const message: DeviceCommand = {
      v: PROTOCOL_VERSION,
      type: "command",
      commandId,
      seq,
      command,
      value: value ?? null,
      issuedAt,
      sentAt: now,
      expiresAt: now + COMMAND_TTL_MS,
      issuedBy,
    };
    this.db.run(
      `INSERT INTO commands (command_id, camera_id, command, value_json, issued_by, issued_at, sent_at, seq, status, updated_at, deadline)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'sent', ?, ?)`,
      commandId,
      cameraId,
      command,
      valueJson,
      issuedBy,
      issuedAt,
      now,
      seq,
      now,
      now + COMMAND_TIMEOUT_MS,
    );
    const row = this.db.first<CommandRow>("SELECT * FROM commands WHERE command_id = ?", commandId);
    if (!this.send(device, message)) {
      if (row) this.finishCommand(row, "failed", null, { code: "send_failed", message: "Invio al telefono fallito" });
      return { ok: true };
    }
    if (row) this.broadcastCommandStatus(row);
    if (!["set_zoom", "zoom_in", "zoom_out", "focus_point", "set_exposure"].includes(command)) {
      this.logEvent(cameraId, "info", "regia", `Comando ${command}${valueJson ? ` ${valueJson}` : ""} da ${issuedBy}`);
    }
    return { ok: true };
  }

  private finishCommand(row: CommandRow, status: CommandStatus, result: Record<string, unknown> | null, error: ErrorInfo | null): void {
    const now = Date.now();
    this.db.run(
      "UPDATE commands SET status = ?, result_json = ?, error_json = ?, updated_at = ? WHERE command_id = ?",
      status,
      result ? JSON.stringify(result) : null,
      error ? JSON.stringify(error) : null,
      now,
      row.command_id,
    );
    this.broadcastCommandStatus({
      ...row,
      status,
      result_json: result ? JSON.stringify(result) : null,
      error_json: error ? JSON.stringify(error) : null,
      updated_at: now,
    });
    if (status !== "completed") {
      this.logEvent(row.camera_id, status === "timeout" ? "warning" : "error", "regia", `Comando ${row.command}: ${status}${error ? ` – ${error.message}` : ""}`);
    }
  }

  // -------------------------------------------------------------------------
  // Broadcast helpers
  // -------------------------------------------------------------------------

  private send(ws: WebSocket, message: unknown): boolean {
    try {
      ws.send(JSON.stringify(message));
      return true;
    } catch {
      return false;
    }
  }

  private closeSocket(ws: WebSocket, code: number, reason: string): void {
    try {
      ws.close(code, reason);
    } catch {
      // already closed
    }
  }

  private deviceSocket(cameraId: string, exclude?: WebSocket): WebSocket | null {
    for (const ws of this.ctx.getWebSockets(`cam:${cameraId}`)) {
      if (ws !== exclude && ws.readyState === WebSocket.READY_STATE_OPEN) return ws;
    }
    return null;
  }

  private broadcastControl(message: unknown): void {
    const payload = JSON.stringify(message);
    for (const ws of this.ctx.getWebSockets("control")) {
      try {
        ws.send(payload);
      } catch {
        // ignore sockets that are closing
      }
    }
  }

  private broadcastCamera(camera: CameraRow, excludeDevice?: WebSocket): void {
    this.broadcastControl({ v: PROTOCOL_VERSION, type: "camera_update", camera: this.cameraView(camera, excludeDevice) });
  }

  private broadcastCommandStatus(row: CommandRow): void {
    this.broadcastControl({ v: PROTOCOL_VERSION, type: "command_status", ...commandView(row) });
  }

  private logEvent(cameraId: string | null, level: "info" | "warning" | "error", source: string, message: string): void {
    const ts = Date.now();
    this.db.run(
      "INSERT INTO events (ts, camera_id, level, source, message) VALUES (?, ?, ?, ?, ?)",
      ts,
      cameraId,
      level,
      source,
      message.slice(0, 500),
    );
    const id = this.db.first<{ id: number }>("SELECT last_insert_rowid() AS id")?.id ?? 0;
    this.broadcastControl({
      v: PROTOCOL_VERSION,
      type: "event",
      event: eventView({ id, ts, camera_id: cameraId, level, source, message: message.slice(0, 500) }),
    });
  }

  private cameraView(camera: CameraRow, excludeDevice?: WebSocket): CameraView {
    const configured = streamApiConfigured(this.env);
    let cfState: CloudflareIngestState;
    if (!configured) cfState = "unconfigured";
    else if (!camera.live_input_id) cfState = "unconfigured";
    else cfState = (camera.cf_state as CloudflareIngestState | null) ?? "unknown";
    return {
      id: camera.id,
      slot: camera.slot,
      name: camera.name,
      online: this.deviceSocket(camera.id, excludeDevice) !== null,
      activated: camera.activated_at !== null,
      lastSeenAt: camera.last_seen_at,
      device: { model: camera.device_model, appVersion: camera.app_version, osVersion: camera.os_version },
      capabilities: parseJson<DeviceCapabilities>(camera.capabilities_json),
      state: parseJson<DeviceState>(camera.state_json),
      telemetry: this.telemetry.get(camera.id) ?? parseJson<Telemetry>(camera.telemetry_json),
      cloudflare: {
        configured,
        liveInputId: camera.live_input_id,
        state: cfState,
        status: camera.cf_status,
        statusAt: camera.cf_status_at,
        error: camera.cf_error,
      },
      playback: playbackUrls(this.customerCode(), camera.live_input_id),
    };
  }

  // -------------------------------------------------------------------------
  // Alarm: command timeouts, Cloudflare polling, heartbeats, maintenance
  // -------------------------------------------------------------------------

  private async ensureAlarm(delayMs: number): Promise<void> {
    const target = Date.now() + Math.max(1000, delayMs);
    const current = await this.ctx.storage.getAlarm();
    if (current === null || current > target) await this.ctx.storage.setAlarm(target);
  }

  async alarm(): Promise<void> {
    const now = Date.now();
    const expired = this.db.all<CommandRow>(
      "SELECT * FROM commands WHERE status IN ('sent','received') AND deadline IS NOT NULL AND deadline <= ?",
      now,
    );
    for (const row of expired) {
      this.finishCommand(row, "timeout", null, { code: "ack_timeout", message: "Nessun ACK dal telefono entro il tempo limite" });
    }

    for (const ws of this.ctx.getWebSockets("device")) {
      const att = ws.deserializeAttachment() as DeviceAttachment | null;
      if (att && now - att.lastSeen > HEARTBEAT_TIMEOUT_MS) this.closeSocket(ws, 4008, "heartbeat timeout");
    }
    for (const ws of this.ctx.getWebSockets("control")) {
      const att = ws.deserializeAttachment() as ControlAttachment | null;
      if (att && att.expiresAt <= now) this.closeSocket(ws, 4003, "session expired");
    }

    const pollIntervalMs = intVar(this.env.CF_POLL_INTERVAL_SECONDS, 20, 10, 300) * 1000;
    const active = this.activeCameras();
    if (active.length > 0 && now - this.lastCloudflarePoll >= pollIntervalMs - 1000) {
      this.lastCloudflarePoll = now;
      await this.pollCloudflare(active.map((c) => c.id));
    }

    if (now - this.lastMaintenance >= MAINTENANCE_INTERVAL_MS) {
      this.lastMaintenance = now;
      this.maintenance(now);
    }

    let next = Number.POSITIVE_INFINITY;
    const pending = this.db.first<{ d: number | null }>(
      "SELECT MIN(deadline) AS d FROM commands WHERE status IN ('sent','received') AND deadline IS NOT NULL",
    );
    if (pending?.d) next = Math.min(next, pending.d);
    if (this.activeCameras().length > 0) next = Math.min(next, now + pollIntervalMs);
    if (this.ctx.getWebSockets("device").length > 0) next = Math.min(next, now + 30_000);
    const hasState = this.db.first("SELECT 1 AS x FROM pairings LIMIT 1") || this.db.first("SELECT 1 AS x FROM sessions LIMIT 1");
    if (hasState || this.ctx.getWebSockets("control").length > 0) next = Math.min(next, now + MAINTENANCE_INTERVAL_MS);
    if (Number.isFinite(next)) await this.ctx.storage.setAlarm(Math.max(next, now + 1000));
  }

  private activeCameras(): CameraRow[] {
    if (!streamApiConfigured(this.env)) return [];
    return this.db.cameras().filter((camera) => {
      if (!camera.live_input_id) return false;
      const state = parseJson<DeviceState>(camera.state_json);
      const deviceActive = state !== null && ["connecting", "live", "reconnecting"].includes(state.streamStatus) && this.deviceSocket(camera.id) !== null;
      return deviceActive || camera.cf_state === "live" || camera.cf_state === "reconnecting";
    });
  }

  private async pollCloudflare(cameraIds: string[]): Promise<void> {
    const api = this.streamApi();
    if (!api) return;
    for (const cameraId of cameraIds) {
      const before = this.db.camera(cameraId);
      if (!before?.live_input_id) continue;
      const liveInputId = before.live_input_id;
      try {
        const input = await api.getLiveInput(liveInputId);
        const raw = input.enabled === false ? "disabled" : rawLiveInputStatus(input.status);
        const state = this.applyLiveInputStatus(cameraId, raw, "poll");
        if (state === "live") await this.resolveCustomerCode(api, liveInputId);
        this.watchdog(cameraId, state);
      } catch (err) {
        console.warn("Cloudflare poll failed", cameraId, (err as Error).message);
      }
    }
  }

  /**
   * If the phone believes it is live but Cloudflare reports the input as
   * disconnected on two consecutive polls, ask the phone to reconnect. The
   * command is a real command: it is ACKed or times out like any other.
   */
  private watchdog(cameraId: string, cfState: CloudflareIngestState): void {
    if (!boolVar(this.env.CF_WATCHDOG, true)) return;
    const camera = this.db.camera(cameraId);
    if (!camera) return;
    const state = parseJson<DeviceState>(camera.state_json);
    const telemetry = this.telemetry.get(cameraId);
    const deviceLive = state?.streamStatus === "live" && (telemetry?.uptimeSec ?? 0) >= 30;
    const entry = this.mismatch.get(cameraId) ?? { count: 0, lastAction: 0 };
    if (deviceLive && (cfState === "offline" || cfState === "error")) {
      entry.count++;
      const now = Date.now();
      if (entry.count >= 2 && now - entry.lastAction > WATCHDOG_COOLDOWN_MS && this.deviceSocket(cameraId)) {
        entry.count = 0;
        entry.lastAction = now;
        this.logEvent(cameraId, "warning", "watchdog", "Cloudflare non riceve il flusso mentre il telefono è LIVE: richiesta riconnessione");
        this.dispatchCommand(cameraId, "reconnect", null, "system:watchdog", randomToken(16), now);
      }
      this.mismatch.set(cameraId, entry);
    } else if (entry.count > 0) {
      entry.count = 0;
      this.mismatch.set(cameraId, entry);
    }
  }

  private maintenance(now: number): void {
    this.db.run("DELETE FROM pairings WHERE expires_at < ? AND (claimed_at IS NULL OR claimed_at < ?)", now - TEN_MINUTES, now - 24 * 3600_000);
    this.db.run("DELETE FROM sessions WHERE expires_at < ?", now);
    this.db.run("DELETE FROM commands WHERE updated_at < ?", now - 24 * 3600_000);
    this.db.run("DELETE FROM rate_limits WHERE window_start < ?", now - 3600_000);
    this.db.run("DELETE FROM events WHERE id <= (SELECT MAX(id) FROM events) - ?", MAX_EVENTS);
  }
}

function eventView(row: EventRow) {
  return {
    id: row.id,
    ts: row.ts,
    cameraId: row.camera_id,
    level: row.level,
    source: row.source,
    message: row.message,
  };
}

function commandView(row: CommandRow) {
  return {
    commandId: row.command_id,
    cameraId: row.camera_id,
    command: row.command,
    value: parseJson<unknown>(row.value_json),
    issuedBy: row.issued_by,
    issuedAt: row.issued_at,
    status: row.status,
    result: parseJson<Record<string, unknown>>(row.result_json),
    error: parseJson<ErrorInfo>(row.error_json),
    updatedAt: row.updated_at,
  };
}
