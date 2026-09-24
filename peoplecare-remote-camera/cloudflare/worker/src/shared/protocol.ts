/**
 * PeopleCare Remote Camera — control-plane protocol, version 1.
 *
 * This module is shared by the Cloudflare Worker (server) and the Control Room
 * web app (browser). The Android app implements the same contract in Dart
 * (apps/remote_camera/lib/src/protocol). Golden messages used by the tests of
 * all three components live in docs/protocol-fixtures.
 *
 * It must stay dependency free and must not touch any runtime specific API.
 */

export const PROTOCOL_VERSION = 1 as const;

/** Maximum size of a single WebSocket text frame accepted by the server. */
export const MAX_MESSAGE_BYTES = 32 * 1024;

/** Maximum accepted clock skew between the issuer of a command and the server. */
export const MAX_COMMAND_SKEW_MS = 120_000;

/** Time a device has to execute a command after the server forwarded it. */
export const COMMAND_TTL_MS = 15_000;

/** After this time without a completed ACK the server marks a command as timed out. */
export const COMMAND_TIMEOUT_MS = 25_000;

export const COMMANDS = [
  "start_stream",
  "stop_stream",
  "pause",
  "resume",
  "restart_stream",
  "reconnect",
  "switch_camera",
  "set_zoom",
  "zoom_in",
  "zoom_out",
  "set_audio_enabled",
  "set_video_enabled",
  "set_torch",
  "set_autofocus",
  "focus_point",
  "set_exposure",
  "set_resolution",
  "set_fps",
  "set_bitrate",
  "set_preset",
  "set_record",
] as const;

export type CommandName = (typeof COMMANDS)[number];

export const RESOLUTIONS = ["720p", "1080p"] as const;
export type Resolution = (typeof RESOLUTIONS)[number];

export const FPS_VALUES = [25, 30, 50, 60] as const;
export type Fps = (typeof FPS_VALUES)[number];

export const PRESETS = ["low", "standard", "high"] as const;
export type PresetName = (typeof PRESETS)[number];

export type Facing = "front" | "back";
export type BitrateMode = "auto" | "manual";
export type StreamProtocol = "srt" | "rtmps";

export const MIN_BITRATE_KBPS = 500;
export const MAX_BITRATE_KBPS = 12_000;

export interface BitrateValue {
  mode: BitrateMode;
  kbps?: number;
}

export interface FocusPointValue {
  /** Horizontal position in the transmitted frame, 0 = left, 1 = right. */
  x: number;
  /** Vertical position in the transmitted frame, 0 = top, 1 = bottom. */
  y: number;
}

/** Streaming status reported by the phone. */
export const STREAM_STATUSES = [
  "idle",
  "connecting",
  "live",
  "reconnecting",
  "stopping",
  "error",
] as const;
export type StreamStatus = (typeof STREAM_STATUSES)[number];

export const CAMERA_STATUSES = ["off", "starting", "ready", "error"] as const;
export type CameraStatus = (typeof CAMERA_STATUSES)[number];

/** Status of the live input as seen by Cloudflare Stream. */
export type CloudflareIngestState =
  | "unconfigured"
  | "unknown"
  | "live"
  | "reconnecting"
  | "offline"
  | "disabled"
  | "error";

export type CommandStatus =
  | "sent"
  | "received"
  | "completed"
  | "failed"
  | "rejected"
  | "timeout";

export interface ErrorInfo {
  code: string;
  message: string;
}

// ---------------------------------------------------------------------------
// Capabilities, state and telemetry (phone -> server -> control room)
// ---------------------------------------------------------------------------

export interface FacingCapabilities {
  available: boolean;
  zoom: { supported: boolean; min: number; max: number };
  torch: boolean;
  autofocus: boolean;
  focusPoint: boolean;
  exposure: { supported: boolean; min: number; max: number; step: number };
  /** Frame rates supported per resolution, e.g. {"720p":[25,30,60],"1080p":[25,30]}. */
  fps: Partial<Record<Resolution, number[]>>;
}

export interface DeviceCapabilities {
  facings: Partial<Record<Facing, FacingCapabilities>>;
  resolutions: Resolution[];
  recording: boolean;
  protocols: StreamProtocol[];
  maxBitrateKbps: number;
}

export interface DeviceState {
  cameraStatus: CameraStatus;
  streamStatus: StreamStatus;
  paused: boolean;
  facing: Facing;
  zoom: number;
  torch: boolean;
  autofocus: boolean;
  exposure: number;
  videoEnabled: boolean;
  audioEnabled: boolean;
  recording: boolean;
  resolution: Resolution;
  fps: number;
  bitrateMode: BitrateMode;
  targetBitrateKbps: number;
  protocol: StreamProtocol;
  orientation: "landscape" | "portrait";
  lastError?: ErrorInfo | null;
}

export interface Telemetry {
  ts: number;
  streamStatus: StreamStatus;
  network: {
    type: "wifi" | "cellular" | "ethernet" | "vpn" | "other" | "none";
    metered?: boolean;
    validated?: boolean;
    uplinkKbps?: number | null;
  };
  bitrateKbps: number;
  uploadKbps?: number | null;
  queuePercent?: number | null;
  fps: number;
  resolution: string;
  battery: { percent: number | null; charging: boolean; temperatureC?: number | null };
  thermal?: string | null;
  facing: Facing;
  zoom: number;
  torch: boolean;
  micEnabled: boolean;
  videoEnabled: boolean;
  audioEnabled: boolean;
  uptimeSec: number;
  reconnects: number;
  recentErrors: Array<{ ts: number; code: string; message: string }>;
  recording?: { active: boolean; freeBytes?: number | null } | null;
}

// ---------------------------------------------------------------------------
// Streaming configuration delivered to the phone (never to the control room)
// ---------------------------------------------------------------------------

export interface StreamEndpoint {
  protocol: StreamProtocol;
  /** Base URL as returned by Cloudflare, e.g. the SRT URL of the live input. */
  url: string;
  host: string;
  port: number;
  /** SRT only. */
  streamId?: string;
  /** SRT only. */
  passphrase?: string;
  /** RTMPS only. */
  streamKey?: string;
}

export interface CameraStreamingConfig {
  cameraId: string;
  cameraName: string;
  protocol: StreamProtocol;
  url: string;
  host: string;
  port: number;
  streamId?: string;
  passphrase?: string;
  streamKey?: string;
  fallback?: StreamEndpoint | null;
  resolution: Resolution;
  fps: number;
  videoBitrateKbps: number;
  audioBitrateKbps: number;
  bitrateMode: BitrateMode;
  keyframeIntervalSec: number;
  srtLatencyMs: number;
  issuedAt: number;
}

// ---------------------------------------------------------------------------
// Messages
// ---------------------------------------------------------------------------

export interface BaseMessage {
  v: typeof PROTOCOL_VERSION;
  type: string;
}

/** Control room -> server. */
export interface CommandRequest extends BaseMessage {
  type: "command";
  commandId: string;
  cameraId: string;
  command: CommandName;
  value?: unknown;
  issuedAt: number;
}

/** Server -> phone. */
export interface DeviceCommand extends BaseMessage {
  type: "command";
  commandId: string;
  seq: number;
  command: CommandName;
  value?: unknown;
  issuedAt: number;
  sentAt: number;
  expiresAt: number;
  issuedBy: string;
}

/** Phone -> server. */
export interface AckMessage extends BaseMessage {
  type: "ack";
  commandId: string;
  stage: "received" | "completed";
  ok: boolean;
  result?: Record<string, unknown> | null;
  error?: ErrorInfo | null;
  ts: number;
}

export type ValidationResult<T> = { ok: true; value: T } | { ok: false; error: string };

// ---------------------------------------------------------------------------
// Validation helpers (hand written to keep the bundle dependency free)
// ---------------------------------------------------------------------------

const ID_RE = /^[A-Za-z0-9_-]{8,64}$/;
export const COMMAND_ID_RE = /^[A-Za-z0-9_-]{16,64}$/;

export function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

export function isFiniteNumber(value: unknown): value is number {
  return typeof value === "number" && Number.isFinite(value);
}

export function isCommandName(value: unknown): value is CommandName {
  return typeof value === "string" && (COMMANDS as readonly string[]).includes(value);
}

export function isValidId(value: unknown): value is string {
  return typeof value === "string" && ID_RE.test(value);
}

function fail<T>(error: string): ValidationResult<T> {
  return { ok: false, error };
}

/**
 * Validates and normalizes the value of a command.
 * Returns the normalized value (e.g. rounded numbers) or an error.
 */
export function validateCommandValue(command: CommandName, value: unknown): ValidationResult<unknown> {
  switch (command) {
    case "start_stream":
    case "stop_stream":
    case "pause":
    case "resume":
    case "restart_stream":
    case "reconnect":
      if (value !== undefined && value !== null) return fail("value must be empty");
      return { ok: true, value: null };
    case "zoom_in":
    case "zoom_out":
      if (value === undefined || value === null) return { ok: true, value: null };
      if (!isFiniteNumber(value) || value <= 0 || value > 5) return fail("step must be a number in (0, 5]");
      return { ok: true, value };
    case "switch_camera":
      if (value !== "front" && value !== "back") return fail("value must be 'front' or 'back'");
      return { ok: true, value };
    case "set_zoom":
      if (!isFiniteNumber(value) || value < 0.1 || value > 100) return fail("zoom must be a number in [0.1, 100]");
      return { ok: true, value: Math.round(value * 100) / 100 };
    case "set_audio_enabled":
    case "set_video_enabled":
    case "set_torch":
    case "set_autofocus":
    case "set_record":
      if (typeof value !== "boolean") return fail("value must be a boolean");
      return { ok: true, value };
    case "focus_point": {
      if (!isRecord(value)) return fail("value must be {x, y}");
      const { x, y } = value;
      if (!isFiniteNumber(x) || !isFiniteNumber(y) || x < 0 || x > 1 || y < 0 || y > 1) {
        return fail("x and y must be numbers in [0, 1]");
      }
      return { ok: true, value: { x, y } };
    }
    case "set_exposure":
      if (!isFiniteNumber(value) || !Number.isInteger(value) || value < -100 || value > 100) {
        return fail("exposure must be an integer index in [-100, 100]");
      }
      return { ok: true, value };
    case "set_resolution":
      if (!(RESOLUTIONS as readonly unknown[]).includes(value)) return fail("resolution must be 720p or 1080p");
      return { ok: true, value };
    case "set_fps":
      if (!(FPS_VALUES as readonly unknown[]).includes(value)) return fail("fps must be one of 25, 30, 50, 60");
      return { ok: true, value };
    case "set_bitrate": {
      if (!isRecord(value)) return fail("value must be {mode, kbps}");
      const { mode, kbps } = value;
      if (mode === "auto") {
        if (kbps === undefined || kbps === null) return { ok: true, value: { mode } };
      } else if (mode !== "manual") {
        return fail("mode must be auto or manual");
      }
      if (!isFiniteNumber(kbps) || kbps < MIN_BITRATE_KBPS || kbps > MAX_BITRATE_KBPS) {
        return fail(`kbps must be in [${MIN_BITRATE_KBPS}, ${MAX_BITRATE_KBPS}]`);
      }
      return { ok: true, value: { mode, kbps: Math.round(kbps) } };
    }
    case "set_preset":
      if (!(PRESETS as readonly unknown[]).includes(value)) return fail("preset must be low, standard or high");
      return { ok: true, value };
  }
}

/** Validates a command sent by a control room client. */
export function validateCommandRequest(
  input: unknown,
  now: number,
  maxSkewMs = MAX_COMMAND_SKEW_MS,
): ValidationResult<CommandRequest> {
  if (!isRecord(input)) return fail("message must be an object");
  if (input.v !== PROTOCOL_VERSION) return fail("unsupported protocol version");
  if (input.type !== "command") return fail("type must be command");
  if (typeof input.commandId !== "string" || !COMMAND_ID_RE.test(input.commandId)) {
    return fail("invalid commandId");
  }
  if (!isValidId(input.cameraId)) return fail("invalid cameraId");
  if (!isCommandName(input.command)) return fail("unknown command");
  if (!isFiniteNumber(input.issuedAt)) return fail("issuedAt must be a timestamp in ms");
  if (Math.abs(now - input.issuedAt) > maxSkewMs) return fail("stale or future command (check the PC clock)");
  const value = validateCommandValue(input.command, input.value);
  if (!value.ok) return fail(value.error);
  return {
    ok: true,
    value: {
      v: PROTOCOL_VERSION,
      type: "command",
      commandId: input.commandId,
      cameraId: input.cameraId,
      command: input.command,
      value: value.value,
      issuedAt: input.issuedAt,
    },
  };
}

/** Validates an ACK sent by a phone. */
export function validateAck(input: unknown): ValidationResult<AckMessage> {
  if (!isRecord(input)) return fail("message must be an object");
  if (input.v !== PROTOCOL_VERSION) return fail("unsupported protocol version");
  if (input.type !== "ack") return fail("type must be ack");
  if (typeof input.commandId !== "string" || !COMMAND_ID_RE.test(input.commandId)) {
    return fail("invalid commandId");
  }
  if (input.stage !== "received" && input.stage !== "completed") return fail("invalid stage");
  if (typeof input.ok !== "boolean") return fail("ok must be a boolean");
  let error: ErrorInfo | null = null;
  if (input.error !== undefined && input.error !== null) {
    if (!isRecord(input.error) || typeof input.error.code !== "string" || typeof input.error.message !== "string") {
      return fail("invalid error");
    }
    error = { code: input.error.code.slice(0, 64), message: input.error.message.slice(0, 500) };
  }
  if (!input.ok && input.stage === "completed" && !error) return fail("a failed ack needs an error");
  let result: Record<string, unknown> | null = null;
  if (input.result !== undefined && input.result !== null) {
    if (!isRecord(input.result)) return fail("result must be an object");
    result = input.result;
  }
  return {
    ok: true,
    value: {
      v: PROTOCOL_VERSION,
      type: "ack",
      commandId: input.commandId,
      stage: input.stage,
      ok: input.ok,
      result,
      error,
      ts: isFiniteNumber(input.ts) ? input.ts : 0,
    },
  };
}

// ---------------------------------------------------------------------------
// Sanitizers: the server only forwards known fields to the control room.
// ---------------------------------------------------------------------------

function num(value: unknown, fallback: number, min = -Infinity, max = Infinity): number {
  return isFiniteNumber(value) ? Math.min(max, Math.max(min, value)) : fallback;
}

function optNum(value: unknown, min = -Infinity, max = Infinity): number | null {
  return isFiniteNumber(value) ? Math.min(max, Math.max(min, value)) : null;
}

function str<T extends string>(value: unknown, allowed: readonly T[], fallback: T): T {
  return typeof value === "string" && (allowed as readonly string[]).includes(value) ? (value as T) : fallback;
}

function text(value: unknown, max: number): string {
  return typeof value === "string" ? value.slice(0, max) : "";
}

function sanitizeFacingCapabilities(input: unknown): FacingCapabilities | undefined {
  if (!isRecord(input)) return undefined;
  const zoom = isRecord(input.zoom) ? input.zoom : {};
  const exposure = isRecord(input.exposure) ? input.exposure : {};
  const fpsIn = isRecord(input.fps) ? input.fps : {};
  const fps: Partial<Record<Resolution, number[]>> = {};
  for (const res of RESOLUTIONS) {
    const list = fpsIn[res];
    if (Array.isArray(list)) {
      fps[res] = list.filter((f): f is number => isFiniteNumber(f) && f > 0 && f <= 120).slice(0, 8);
    }
  }
  return {
    available: input.available === true,
    zoom: {
      supported: zoom.supported === true,
      min: num(zoom.min, 1, 0.1, 100),
      max: num(zoom.max, 1, 0.1, 100),
    },
    torch: input.torch === true,
    autofocus: input.autofocus === true,
    focusPoint: input.focusPoint === true,
    exposure: {
      supported: exposure.supported === true,
      min: num(exposure.min, 0, -100, 100),
      max: num(exposure.max, 0, -100, 100),
      step: num(exposure.step, 0, 0, 10),
    },
    fps,
  };
}

export function sanitizeCapabilities(input: unknown): DeviceCapabilities | null {
  if (!isRecord(input)) return null;
  const facingsIn = isRecord(input.facings) ? input.facings : {};
  const facings: Partial<Record<Facing, FacingCapabilities>> = {};
  for (const facing of ["front", "back"] as const) {
    const caps = sanitizeFacingCapabilities(facingsIn[facing]);
    if (caps) facings[facing] = caps;
  }
  const resolutions = Array.isArray(input.resolutions)
    ? (input.resolutions.filter((r) => (RESOLUTIONS as readonly unknown[]).includes(r)) as Resolution[])
    : [];
  const protocols = Array.isArray(input.protocols)
    ? (input.protocols.filter((p) => p === "srt" || p === "rtmps") as StreamProtocol[])
    : [];
  return {
    facings,
    resolutions,
    recording: input.recording === true,
    protocols,
    maxBitrateKbps: num(input.maxBitrateKbps, MAX_BITRATE_KBPS, MIN_BITRATE_KBPS, 50_000),
  };
}

export function sanitizeState(input: unknown): DeviceState | null {
  if (!isRecord(input)) return null;
  let lastError: ErrorInfo | null = null;
  if (isRecord(input.lastError) && typeof input.lastError.code === "string") {
    lastError = { code: text(input.lastError.code, 64), message: text(input.lastError.message, 300) };
  }
  return {
    cameraStatus: str(input.cameraStatus, CAMERA_STATUSES, "off"),
    streamStatus: str(input.streamStatus, STREAM_STATUSES, "idle"),
    paused: input.paused === true,
    facing: str(input.facing, ["front", "back"] as const, "back"),
    zoom: num(input.zoom, 1, 0.1, 100),
    torch: input.torch === true,
    autofocus: input.autofocus === true,
    exposure: num(input.exposure, 0, -100, 100),
    videoEnabled: input.videoEnabled !== false,
    audioEnabled: input.audioEnabled !== false,
    recording: input.recording === true,
    resolution: str(input.resolution, RESOLUTIONS, "1080p"),
    fps: num(input.fps, 30, 1, 120),
    bitrateMode: str(input.bitrateMode, ["auto", "manual"] as const, "auto"),
    targetBitrateKbps: num(input.targetBitrateKbps, 0, 0, 50_000),
    protocol: str(input.protocol, ["srt", "rtmps"] as const, "srt"),
    orientation: str(input.orientation, ["landscape", "portrait"] as const, "landscape"),
    lastError,
  };
}

export function sanitizeTelemetry(input: unknown, now: number): Telemetry | null {
  if (!isRecord(input)) return null;
  const network = isRecord(input.network) ? input.network : {};
  const battery = isRecord(input.battery) ? input.battery : {};
  const recording = isRecord(input.recording) ? input.recording : null;
  const errors = Array.isArray(input.recentErrors) ? input.recentErrors : [];
  return {
    ts: num(input.ts, now, 0, now + 60_000),
    streamStatus: str(input.streamStatus, STREAM_STATUSES, "idle"),
    network: {
      type: str(network.type, ["wifi", "cellular", "ethernet", "vpn", "other", "none"] as const, "other"),
      metered: network.metered === true,
      validated: network.validated === true,
      uplinkKbps: optNum(network.uplinkKbps, 0, 10_000_000),
    },
    bitrateKbps: num(input.bitrateKbps, 0, 0, 1_000_000),
    uploadKbps: optNum(input.uploadKbps, 0, 1_000_000),
    queuePercent: optNum(input.queuePercent, 0, 100),
    fps: num(input.fps, 0, 0, 240),
    resolution: text(input.resolution, 16),
    battery: {
      percent: optNum(battery.percent, 0, 100),
      charging: battery.charging === true,
      temperatureC: optNum(battery.temperatureC, -40, 150),
    },
    thermal: typeof input.thermal === "string" ? text(input.thermal, 16) : null,
    facing: str(input.facing, ["front", "back"] as const, "back"),
    zoom: num(input.zoom, 1, 0.1, 100),
    torch: input.torch === true,
    micEnabled: input.micEnabled !== false,
    videoEnabled: input.videoEnabled !== false,
    audioEnabled: input.audioEnabled !== false,
    uptimeSec: num(input.uptimeSec, 0, 0, 10 * 365 * 86400),
    reconnects: num(input.reconnects, 0, 0, 1_000_000),
    recentErrors: errors
      .filter(isRecord)
      .slice(-5)
      .map((e) => ({ ts: num(e.ts, 0, 0), code: text(e.code, 64), message: text(e.message, 300) })),
    recording: recording
      ? { active: recording.active === true, freeBytes: optNum(recording.freeBytes, 0) }
      : null,
  };
}

/** Normalizes a pairing code typed by a human: removes separators, fixes ambiguous characters. */
export function normalizePairingCode(input: string): string {
  return input
    .toUpperCase()
    .replace(/[\s-]/g, "")
    .replace(/O/g, "0")
    .replace(/[IL]/g, "1");
}

export const PAIRING_ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";
export const PAIRING_CODE_LENGTH = 8;
const PAIRING_RE = new RegExp(`^[${PAIRING_ALPHABET}]{${PAIRING_CODE_LENGTH}}$`);

export function isValidPairingCode(normalized: string): boolean {
  return PAIRING_RE.test(normalized);
}

export function formatPairingCode(normalized: string): string {
  return `${normalized.slice(0, 4)}-${normalized.slice(4)}`;
}

/**
 * Extracts a pairing code from the content of the QR code shown by the phone.
 * Format: "PCRC:1:<CODE>" (see docs/PAIRING.md). Plain codes are accepted too.
 */
export function parsePairingQr(content: string): string | null {
  const trimmed = content.trim();
  const match = /^PCRC:1:([0-9A-Za-z-]{8,9})(?::.*)?$/.exec(trimmed);
  const candidate = normalizePairingCode(match ? match[1] : trimmed);
  return isValidPairingCode(candidate) ? candidate : null;
}
