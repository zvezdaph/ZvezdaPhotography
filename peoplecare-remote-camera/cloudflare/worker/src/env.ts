import type { StudioDurableObject } from "./studio";

/**
 * Bindings, variables and secrets of the Worker.
 *
 * Secrets (set with `wrangler secret put <NAME>`, never committed):
 *  - CLOUDFLARE_ACCOUNT_ID, CLOUDFLARE_API_TOKEN: Stream Live Input API access.
 *  - CONTROL_ROOM_PASSWORD: password of the control room (min 12 chars).
 *  - STREAM_WEBHOOK_SECRET: optional, secret of the Cloudflare Notifications webhook.
 *
 * Variables are documented in docs/CLOUDFLARE_SETUP.md and .env.example.
 */
export interface Env {
  STUDIO: DurableObjectNamespace<StudioDurableObject>;
  ASSETS?: Fetcher;
  RL_PUBLIC?: RateLimit;

  CLOUDFLARE_ACCOUNT_ID?: string;
  CLOUDFLARE_API_TOKEN?: string;
  CONTROL_ROOM_PASSWORD?: string;
  STREAM_WEBHOOK_SECRET?: string;

  APP_NAME?: string;
  ALLOWED_ORIGINS?: string;
  SESSION_TTL_HOURS?: string;
  PAIRING_TTL_MINUTES?: string;
  CLOUDFLARE_STREAM_CUSTOMER_CODE?: string;
  STREAM_RECORDING_MODE?: string;
  STREAM_DELETE_RECORDING_AFTER_DAYS?: string;
  STREAM_PREFER_LOW_LATENCY?: string;
  STREAM_ALLOWED_ORIGINS?: string;
  DEFAULT_RESOLUTION?: string;
  DEFAULT_FPS?: string;
  DEFAULT_VIDEO_BITRATE_KBPS?: string;
  DEFAULT_AUDIO_BITRATE_KBPS?: string;
  SRT_LATENCY_MS?: string;
  REVOKE_ACTION?: string;
  CF_WATCHDOG?: string;
  CF_POLL_INTERVAL_SECONDS?: string;
  DO_LOCATION_HINT?: string;
  /** Test only: base URL of the Cloudflare API (defaults to https://api.cloudflare.com/client/v4). */
  CLOUDFLARE_API_BASE?: string;
}

export function intVar(value: string | undefined, fallback: number, min: number, max: number): number {
  const parsed = value === undefined || value.trim() === "" ? NaN : Number(value);
  if (!Number.isFinite(parsed)) return fallback;
  return Math.min(max, Math.max(min, Math.round(parsed)));
}

export function boolVar(value: string | undefined, fallback: boolean): boolean {
  if (value === undefined || value.trim() === "") return fallback;
  return ["1", "true", "yes", "on"].includes(value.trim().toLowerCase());
}

export function listVar(value: string | undefined): string[] {
  if (!value) return [];
  return value
    .split(",")
    .map((v) => v.trim())
    .filter((v) => v.length > 0);
}

function isRealSecret(value: string | undefined): boolean {
  return Boolean(value && value.trim().length > 0 && !value.startsWith("PLACEHOLDER"));
}

/** True when both Cloudflare API secrets are set (placeholders from the examples do not count). */
export function streamApiConfigured(env: Env): boolean {
  return isRealSecret(env.CLOUDFLARE_ACCOUNT_ID) && isRealSecret(env.CLOUDFLARE_API_TOKEN);
}
