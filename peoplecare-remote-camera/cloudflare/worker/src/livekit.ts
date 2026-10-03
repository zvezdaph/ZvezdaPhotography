import type { Env } from "./env";

const encoder = new TextEncoder();

function base64Url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");
}

function encodeJson(value: unknown): string {
  return base64Url(encoder.encode(JSON.stringify(value)));
}

function configuredSecret(value: string | undefined): string | null {
  const trimmed = value?.trim() ?? "";
  return trimmed && !trimmed.startsWith("PLACEHOLDER") ? trimmed : null;
}

export function liveKitConfigured(env: Env): boolean {
  return Boolean(
    configuredSecret(env.LIVEKIT_URL) &&
      configuredSecret(env.LIVEKIT_API_KEY) &&
      configuredSecret(env.LIVEKIT_API_SECRET),
  );
}

export function liveKitServerUrl(env: Env): string {
  const value = configuredSecret(env.LIVEKIT_URL);
  if (!value) throw new Error("LIVEKIT_URL non configurato");
  const url = new URL(value);
  if (url.protocol !== "wss:" && url.protocol !== "ws:") {
    throw new Error("LIVEKIT_URL deve iniziare con wss:// (ws:// solo in sviluppo)");
  }
  return url.toString().replace(/\/$/, "");
}

export interface LiveKitGrantOptions {
  room: string;
  identity: string;
  canPublish: boolean;
  canSubscribe: boolean;
  ttlSeconds?: number;
}

/**
 * Creates a LiveKit HS256 room token without exposing the API secret to clients.
 * LiveKit room/identity values are opaque PeopleCare IDs (never names or PII).
 */
export async function createLiveKitJoinToken(env: Env, options: LiveKitGrantOptions): Promise<string> {
  const apiKey = configuredSecret(env.LIVEKIT_API_KEY);
  const apiSecret = configuredSecret(env.LIVEKIT_API_SECRET);
  if (!apiKey || !apiSecret) throw new Error("LiveKit non configurato");

  const now = Math.floor(Date.now() / 1000);
  const ttl = Math.min(3600, Math.max(120, options.ttlSeconds ?? 600));
  const header = encodeJson({ alg: "HS256", typ: "JWT" });
  const payload = encodeJson({
    iss: apiKey,
    sub: options.identity,
    nbf: now - 5,
    exp: now + ttl,
    video: {
      roomJoin: true,
      room: options.room,
      canPublish: options.canPublish,
      canSubscribe: options.canSubscribe,
      canPublishData: false,
    },
  });
  const unsigned = `${header}.${payload}`;
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(apiSecret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = new Uint8Array(await crypto.subtle.sign("HMAC", key, encoder.encode(unsigned)));
  return `${unsigned}.${base64Url(signature)}`;
}
