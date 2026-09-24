import type { Env } from "./env";
import { intVar } from "./env";
import type { LiveInput } from "./cloudflare/stream";
import { parseEndpointUrl } from "./cloudflare/stream";
import type {
  CameraStreamingConfig,
  CommandName,
  DeviceCapabilities,
  DeviceState,
  ErrorInfo,
  Resolution,
} from "./shared/protocol";
import { MAX_BITRATE_KBPS, MIN_BITRATE_KBPS, RESOLUTIONS } from "./shared/protocol";

/**
 * Server side capability check (defense in depth: the phone checks again).
 * When the phone has not reported its capabilities yet the command is let
 * through and the phone decides.
 */
export function checkCommandSupported(
  caps: DeviceCapabilities | null,
  state: DeviceState | null,
  command: CommandName,
  value: unknown,
): ErrorInfo | null {
  if (!caps) return null;
  const facing = state?.facing ?? "back";
  const current = caps.facings[facing];
  const unsupported = (what: string): ErrorInfo => ({
    code: "unsupported",
    message: `${what} non supportato da questo dispositivo`,
  });
  switch (command) {
    case "switch_camera": {
      const target = caps.facings[value as "front" | "back"];
      return target?.available ? null : unsupported(`Camera ${value === "front" ? "frontale" : "posteriore"}`);
    }
    case "set_zoom":
    case "zoom_in":
    case "zoom_out":
      return current?.zoom.supported ? null : unsupported("Zoom");
    case "set_torch":
      return value === false || current?.torch ? null : unsupported("Torcia");
    case "set_autofocus":
      return current?.autofocus ? null : unsupported("Autofocus");
    case "focus_point":
      return current?.focusPoint ? null : unsupported("Focus point");
    case "set_exposure":
      return current?.exposure.supported ? null : unsupported("Esposizione");
    case "set_resolution":
      return caps.resolutions.includes(value as Resolution) ? null : unsupported(`Risoluzione ${String(value)}`);
    case "set_fps": {
      const resolution = state?.resolution ?? "1080p";
      const list = current?.fps[resolution];
      if (!list || list.length === 0) return null;
      return list.includes(value as number) ? null : unsupported(`${String(value)} fps a ${resolution}`);
    }
    case "set_record":
      return value === false || caps.recording ? null : unsupported("Registrazione locale");
    default:
      return null;
  }
}

export interface StreamDefaults {
  resolution: Resolution;
  fps: number;
  videoBitrateKbps: number;
  audioBitrateKbps: number;
  srtLatencyMs: number;
}

export function streamDefaults(env: Env): StreamDefaults {
  const resolution = (RESOLUTIONS as readonly string[]).includes(env.DEFAULT_RESOLUTION ?? "")
    ? (env.DEFAULT_RESOLUTION as Resolution)
    : "1080p";
  const fps = [25, 30, 50, 60].includes(Number(env.DEFAULT_FPS)) ? Number(env.DEFAULT_FPS) : 30;
  return {
    resolution,
    fps,
    videoBitrateKbps: intVar(env.DEFAULT_VIDEO_BITRATE_KBPS, 5000, MIN_BITRATE_KBPS, MAX_BITRATE_KBPS),
    audioBitrateKbps: intVar(env.DEFAULT_AUDIO_BITRATE_KBPS, 128, 64, 320),
    srtLatencyMs: intVar(env.SRT_LATENCY_MS, 500, 80, 8000),
  };
}

/**
 * Builds the configuration sent to the phone from a live input.
 * SRT is the primary protocol, RTMPS the fallback. Nothing else of the live
 * input (playback keys, WebRTC URLs) is forwarded to the phone.
 */
export function buildStreamingConfig(
  camera: { id: string; name: string },
  liveInput: LiveInput,
  defaults: StreamDefaults,
  now: number,
): CameraStreamingConfig | ErrorInfo {
  if (liveInput.enabled === false) {
    return { code: "live_input_disabled", message: "Il live input Cloudflare è disabilitato dalla regia" };
  }
  const srt = parseEndpointUrl(liveInput.srt?.url);
  const srtStreamId = liveInput.srt?.streamId;
  const rtmps = parseEndpointUrl(liveInput.rtmps?.url);
  const rtmpsKey = liveInput.rtmps?.streamKey;
  const common = {
    cameraId: camera.id,
    cameraName: camera.name,
    resolution: defaults.resolution,
    fps: defaults.fps,
    videoBitrateKbps: defaults.videoBitrateKbps,
    audioBitrateKbps: defaults.audioBitrateKbps,
    bitrateMode: "auto" as const,
    keyframeIntervalSec: 2,
    srtLatencyMs: defaults.srtLatencyMs,
    issuedAt: now,
  };
  const rtmpsEndpoint =
    rtmps && rtmpsKey ? { protocol: "rtmps" as const, url: rtmps.url, host: rtmps.host, port: rtmps.port, streamKey: rtmpsKey } : null;
  if (srt && srtStreamId) {
    return {
      ...common,
      protocol: "srt",
      url: srt.url,
      host: srt.host,
      port: srt.port,
      streamId: srtStreamId,
      passphrase: liveInput.srt?.passphrase ?? "",
      fallback: rtmpsEndpoint,
    };
  }
  if (rtmpsEndpoint) {
    return {
      ...common,
      protocol: "rtmps",
      url: rtmpsEndpoint.url,
      host: rtmpsEndpoint.host,
      port: rtmpsEndpoint.port,
      streamKey: rtmpsEndpoint.streamKey,
      fallback: null,
    };
  }
  return { code: "live_input_incomplete", message: "Il live input non contiene credenziali SRT né RTMPS" };
}

export function isErrorInfo(value: unknown): value is ErrorInfo {
  return typeof value === "object" && value !== null && "code" in value && "message" in value && !("cameraId" in value);
}

/** Operator names are shown in logs: keep them short and printable. */
export function sanitizeName(input: unknown, max: number): string | null {
  if (typeof input !== "string") return null;
  const cleaned = input.replace(/[\u0000-\u001f\u007f]/g, "").replace(/\s+/g, " ").trim();
  if (cleaned.length === 0 || cleaned.length > max) return null;
  return cleaned;
}
