import type { CameraView } from "./types";
import type { FacingCapabilities, Resolution } from "@protocol";

export interface ControlAvailability {
  online: boolean;
  start: boolean;
  pause: boolean;
  resume: boolean;
  stop: boolean;
  reconnect: boolean;
  restart: boolean;
  front: boolean;
  back: boolean;
  zoom: { enabled: boolean; min: number; max: number; value: number };
  torch: boolean;
  autofocus: boolean;
  focusPoint: boolean;
  exposure: { enabled: boolean; min: number; max: number; step: number; value: number };
  mic: boolean;
  video: boolean;
  resolutions: Array<{ value: Resolution; enabled: boolean }>;
  fps: Array<{ value: number; enabled: boolean }>;
  bitrate: boolean;
  record: boolean;
  /** Human readable reason shown when a control is disabled. */
  reasons: Partial<Record<string, string>>;
}

const ALL_FPS = [25, 30, 50, 60];

export function currentFacingCaps(camera: CameraView): FacingCapabilities | null {
  const facing = camera.state?.facing ?? "back";
  return camera.capabilities?.facings[facing] ?? null;
}

/**
 * Computes which controls are really usable for a camera. A control is only
 * enabled when the phone is connected AND reported the capability: nothing is
 * shown as working if the hardware does not support it.
 */
export function controlAvailability(camera: CameraView): ControlAvailability {
  const online = camera.online;
  const state = camera.state;
  const caps = camera.capabilities;
  const facingCaps = currentFacingCaps(camera);
  const status = state?.streamStatus ?? "idle";
  const cameraReady = state?.cameraStatus === "ready";
  const streaming = status === "connecting" || status === "live" || status === "reconnecting";
  const reasons: Partial<Record<string, string>> = {};
  if (!online) reasons.all = "Telefono non connesso alla regia";
  else if (!state) reasons.all = "In attesa dello stato del telefono";

  const known = online && state !== null && caps !== null;
  const resolution = state?.resolution ?? "1080p";

  const fpsSupported = facingCaps?.fps[resolution] ?? [];
  if (known && !facingCaps?.torch) reasons.torch = "Torcia non disponibile su questa camera";
  if (known && !facingCaps?.focusPoint) reasons.focusPoint = "Focus point non supportato";
  if (known && !facingCaps?.exposure.supported) reasons.exposure = "Esposizione non regolabile";
  if (known && !facingCaps?.zoom.supported) reasons.zoom = "Zoom non supportato";
  if (known && !caps?.recording) reasons.record = "Registrazione locale non disponibile";

  return {
    online,
    start: online && cameraReady && (status === "idle" || status === "error"),
    pause: online && streaming && !state?.paused,
    resume: online && Boolean(state?.paused),
    stop: online && (streaming || status === "error" || Boolean(state?.paused)),
    reconnect: online && streaming,
    restart: online && streaming,
    front: known && Boolean(caps?.facings.front?.available) && state?.facing !== "front",
    back: known && Boolean(caps?.facings.back?.available) && state?.facing !== "back",
    zoom: {
      enabled: known && Boolean(facingCaps?.zoom.supported) && (facingCaps?.zoom.max ?? 1) > (facingCaps?.zoom.min ?? 1),
      min: facingCaps?.zoom.min ?? 1,
      max: facingCaps?.zoom.max ?? 1,
      value: state?.zoom ?? 1,
    },
    torch: known && Boolean(facingCaps?.torch),
    autofocus: known && Boolean(facingCaps?.autofocus),
    focusPoint: known && Boolean(facingCaps?.focusPoint),
    exposure: {
      enabled: known && Boolean(facingCaps?.exposure.supported) && (facingCaps?.exposure.max ?? 0) > (facingCaps?.exposure.min ?? 0),
      min: facingCaps?.exposure.min ?? 0,
      max: facingCaps?.exposure.max ?? 0,
      step: facingCaps?.exposure.step ?? 0,
      value: state?.exposure ?? 0,
    },
    mic: known,
    video: known,
    resolutions: (["720p", "1080p"] as const).map((value) => ({
      value,
      enabled: known && Boolean(caps?.resolutions.includes(value)),
    })),
    fps: ALL_FPS.map((value) => ({ value, enabled: known && fpsSupported.includes(value) })),
    bitrate: known,
    record: known && Boolean(caps?.recording),
    reasons,
  };
}

export type TallyState = "live" | "paused" | "reconnecting" | "connecting" | "error" | "ready" | "offline";

/** Tally light of a camera tile (red only when the phone is really live). */
export function tallyState(camera: CameraView): TallyState {
  if (!camera.online) return "offline";
  const state = camera.state;
  if (!state) return "ready";
  if (state.streamStatus === "live") return state.paused ? "paused" : "live";
  if (state.streamStatus === "reconnecting") return "reconnecting";
  if (state.streamStatus === "connecting") return "connecting";
  if (state.streamStatus === "error" || state.cameraStatus === "error") return "error";
  return "ready";
}

export function tallyLabel(state: TallyState): string {
  switch (state) {
    case "live":
      return "LIVE";
    case "paused":
      return "PAUSA";
    case "reconnecting":
      return "RICONNESSIONE";
    case "connecting":
      return "CONNESSIONE";
    case "error":
      return "ERRORE";
    case "ready":
      return "PRONTA";
    case "offline":
      return "OFFLINE";
  }
}

export type Quality = "good" | "fair" | "poor" | "unknown";

/** Connection quality from real telemetry: delivered bitrate vs target, queue and reconnects. */
export function connectionQuality(camera: CameraView): Quality {
  const t = camera.telemetry;
  const s = camera.state;
  if (!camera.online || !t || !s || s.streamStatus !== "live") return "unknown";
  const target = s.targetBitrateKbps || 1;
  const ratio = t.bitrateKbps / target;
  const queue = t.queuePercent ?? 0;
  if (queue > 50 || ratio < 0.5) return "poor";
  if (queue > 15 || ratio < 0.8) return "fair";
  return "good";
}
