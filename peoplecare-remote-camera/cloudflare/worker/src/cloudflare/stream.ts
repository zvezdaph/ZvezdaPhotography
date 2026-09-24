/**
 * Minimal client for the Cloudflare Stream Live Input API.
 *
 * Endpoints and fields follow the official documentation
 * (developers.cloudflare.com/stream/stream-live/start-stream-live/) and the
 * API schema used by the official SDKs:
 *   POST   /accounts/{account_id}/stream/live_inputs
 *   GET    /accounts/{account_id}/stream/live_inputs/{uid}
 *   PUT    /accounts/{account_id}/stream/live_inputs/{uid}
 *   DELETE /accounts/{account_id}/stream/live_inputs/{uid}
 *   POST   /accounts/{account_id}/stream/live_inputs/{uid}/rotate_keys
 *   GET    /accounts/{account_id}/stream/live_inputs/{uid}/videos
 *
 * The API token is only used in the Authorization header and never logged.
 */

export const DEFAULT_API_BASE = "https://api.cloudflare.com/client/v4";

export interface LiveInputRecording {
  mode?: "off" | "automatic";
  requireSignedURLs?: boolean;
  allowedOrigins?: string[] | null;
  hideLiveViewerCount?: boolean;
  timeoutSeconds?: number;
}

export interface LiveInput {
  uid: string;
  created?: string;
  modified?: string;
  enabled?: boolean;
  meta?: Record<string, unknown>;
  recording?: LiveInputRecording;
  deleteRecordingAfterDays?: number | null;
  preferLowLatency?: boolean;
  keysRotatedAt?: string | null;
  rtmps?: { url?: string; streamKey?: string };
  rtmpsPlayback?: { url?: string; streamKey?: string };
  srt?: { url?: string; streamId?: string; passphrase?: string };
  srtPlayback?: { url?: string; streamId?: string; passphrase?: string };
  webRTC?: { url?: string };
  webRTCPlayback?: { url?: string };
  /** Documented as a status string; tolerated as an object as well (see liveStatus.ts). */
  status?: unknown;
}

export interface StreamVideo {
  uid: string;
  preview?: string;
  thumbnail?: string;
  playback?: { hls?: string; dash?: string };
  status?: { state?: string };
  created?: string;
}

export interface CreateLiveInputParams {
  name: string;
  cameraId: string;
  recordingMode: "off" | "automatic";
  deleteRecordingAfterDays?: number | null;
  preferLowLatency?: boolean;
  allowedOrigins?: string[];
}

export class StreamApiError extends Error {
  constructor(
    readonly status: number,
    readonly errors: Array<{ code?: number; message?: string }>,
    message: string,
  ) {
    super(message);
  }
}

interface ApiEnvelope<T> {
  success?: boolean;
  errors?: Array<{ code?: number; message?: string }>;
  result?: T;
}

export class StreamApi {
  private readonly base: string;

  constructor(
    private readonly accountId: string,
    private readonly apiToken: string,
    private readonly fetcher: typeof fetch = fetch,
    base: string = DEFAULT_API_BASE,
  ) {
    this.base = base.replace(/\/+$/, "");
  }

  private url(path: string): string {
    return `${this.base}/accounts/${encodeURIComponent(this.accountId)}/stream${path}`;
  }

  private async request<T>(method: string, path: string, body?: unknown): Promise<T> {
    const headers: Record<string, string> = { Authorization: `Bearer ${this.apiToken}` };
    if (body !== undefined) headers["Content-Type"] = "application/json";
    let response: Response;
    try {
      response = await this.fetcher(this.url(path), {
        method,
        headers,
        body: body === undefined ? undefined : JSON.stringify(body),
      });
    } catch (err) {
      throw new StreamApiError(0, [], `Cloudflare API unreachable: ${(err as Error).message}`);
    }
    if (method === "DELETE" && (response.status === 200 || response.status === 204)) {
      return undefined as T;
    }
    let envelope: ApiEnvelope<T> | null = null;
    try {
      envelope = (await response.json()) as ApiEnvelope<T>;
    } catch {
      envelope = null;
    }
    if (!response.ok || !envelope || envelope.success === false) {
      const errors = envelope?.errors ?? [];
      const detail = errors.map((e) => `${e.code ?? "?"}: ${e.message ?? "error"}`).join("; ");
      throw new StreamApiError(
        response.status,
        errors,
        `Cloudflare API ${method} ${path.replace(/[0-9a-f]{32}/g, ":uid")} failed with HTTP ${response.status}${detail ? ` (${detail})` : ""}`,
      );
    }
    return envelope.result as T;
  }

  createLiveInput(params: CreateLiveInputParams): Promise<LiveInput> {
    const recording: LiveInputRecording = {
      mode: params.recordingMode,
      requireSignedURLs: false,
      hideLiveViewerCount: true,
    };
    if (params.allowedOrigins && params.allowedOrigins.length > 0) recording.allowedOrigins = params.allowedOrigins;
    const body: Record<string, unknown> = {
      meta: { name: params.name, cameraId: params.cameraId, app: "peoplecare-remote-camera" },
      recording,
      enabled: true,
    };
    if (params.deleteRecordingAfterDays) body.deleteRecordingAfterDays = params.deleteRecordingAfterDays;
    if (params.preferLowLatency) body.preferLowLatency = true;
    return this.request<LiveInput>("POST", "/live_inputs", body);
  }

  getLiveInput(uid: string): Promise<LiveInput> {
    return this.request<LiveInput>("GET", `/live_inputs/${encodeURIComponent(uid)}`);
  }

  updateLiveInput(uid: string, body: Record<string, unknown>): Promise<LiveInput> {
    return this.request<LiveInput>("PUT", `/live_inputs/${encodeURIComponent(uid)}`, body);
  }

  setEnabled(uid: string, enabled: boolean): Promise<LiveInput> {
    return this.updateLiveInput(uid, { enabled });
  }

  rotateKeys(uid: string): Promise<LiveInput> {
    return this.request<LiveInput>("POST", `/live_inputs/${encodeURIComponent(uid)}/rotate_keys`);
  }

  async deleteLiveInput(uid: string): Promise<void> {
    await this.request<void>("DELETE", `/live_inputs/${encodeURIComponent(uid)}`);
  }

  listVideos(uid: string): Promise<StreamVideo[]> {
    return this.request<StreamVideo[]>("GET", `/live_inputs/${encodeURIComponent(uid)}/videos`);
  }
}

export interface ParsedEndpoint {
  url: string;
  host: string;
  port: number;
}

/**
 * Parses the URL of an endpoint returned by the API (e.g. the SRT or RTMPS
 * URL). `URL` does not know default ports for srt/rtmps, so they are handled here.
 */
export function parseEndpointUrl(raw: string | undefined): ParsedEndpoint | null {
  if (!raw) return null;
  let url: URL;
  try {
    url = new URL(raw);
  } catch {
    return null;
  }
  const scheme = url.protocol.replace(/:$/, "").toLowerCase();
  if (!url.hostname) return null;
  let port = url.port ? Number(url.port) : NaN;
  if (!Number.isFinite(port)) {
    if (scheme === "rtmps" || scheme === "https") port = 443;
    else if (scheme === "rtmp") port = 1935;
    else return null; // SRT has no default port: the API always returns it explicitly.
  }
  return { url: raw, host: url.hostname, port };
}

const CUSTOMER_RE = /https:\/\/customer-([a-z0-9]+)\.cloudflarestream\.com\//i;

export function extractCustomerCode(...urls: Array<string | undefined>): string | null {
  for (const url of urls) {
    if (!url) continue;
    const match = CUSTOMER_RE.exec(url);
    if (match) return match[1];
  }
  return null;
}

export function playbackUrls(customerCode: string | null | undefined, liveInputId: string | null | undefined) {
  if (!customerCode || !liveInputId || !/^[a-z0-9]+$/i.test(customerCode)) return null;
  const base = `https://customer-${customerCode}.cloudflarestream.com/${liveInputId}`;
  return {
    iframeUrl: `${base}/iframe?autoplay=true&muted=true&preload=auto&controls=true`,
    hlsUrl: `${base}/manifest/video.m3u8`,
  };
}

/** Builds the URL used by OBS/ffmpeg for SRT playback: base URL + streamid + passphrase. */
export function buildSrtUrl(base: string | undefined, streamId: string | undefined, passphrase: string | undefined): string | null {
  if (!base || !streamId) return null;
  const params: string[] = [];
  if (passphrase) params.push(`passphrase=${encodeURIComponent(passphrase)}`);
  params.push(`streamid=${encodeURIComponent(streamId)}`);
  const separator = base.includes("?") ? "&" : "?";
  return `${base}${separator}${params.join("&")}`;
}

export function buildRtmpsUrl(base: string | undefined, streamKey: string | undefined): string | null {
  if (!base || !streamKey) return null;
  return `${base.endsWith("/") ? base : `${base}/`}${streamKey}`;
}
