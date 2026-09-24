import type {
  CloudflareIngestState,
  CommandName,
  DeviceCapabilities,
  DeviceState,
  ErrorInfo,
  Telemetry,
} from "@protocol";

export type { CommandName, DeviceCapabilities, DeviceState, ErrorInfo, Telemetry, CloudflareIngestState };

/** Camera as exposed by the control plane (see cloudflare/worker/src/studio.ts CameraView). */
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

export interface EventView {
  id: number;
  ts: number;
  cameraId: string | null;
  level: "info" | "warning" | "error" | string;
  source: string;
  message: string;
}

export type CommandLifecycle = "pending" | "sent" | "received" | "completed" | "failed" | "rejected" | "timeout";

export interface CommandView {
  commandId: string;
  cameraId: string | null;
  command: string | null;
  value?: unknown;
  issuedBy?: string;
  status: CommandLifecycle;
  result?: Record<string, unknown> | null;
  error?: ErrorInfo | null;
  updatedAt: number;
}

export interface PublicConfig {
  appName: string;
  version: string;
  protocol: number;
  streamConfigured: boolean;
  webhookConfigured: boolean;
  customerCodeKnown: boolean;
  watchdog: boolean;
  maxSlots: number;
}

export interface PlaybackInfo {
  liveInputId: string;
  player: { iframeUrl: string; hlsUrl: string } | null;
  srt: { url: string; streamId: string | null; passphrase: string | null; obsUrl: string | null } | null;
  rtmps: { url: string; streamKey: string | null; obsUrl: string | null } | null;
}
