import type { CameraView, EventView, PlaybackInfo, PublicConfig } from "./types";

export class ApiError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    message: string,
  ) {
    super(message);
  }
}

async function request<T>(path: string, init: RequestInit = {}): Promise<T> {
  const headers = new Headers(init.headers);
  if (init.body !== undefined && !headers.has("Content-Type")) headers.set("Content-Type", "application/json");
  let response: Response;
  try {
    response = await fetch(path, { ...init, headers, credentials: "same-origin", cache: "no-store" });
  } catch {
    throw new ApiError(0, "network", "Server regia non raggiungibile");
  }
  let body: unknown = null;
  try {
    body = await response.json();
  } catch {
    body = null;
  }
  if (!response.ok) {
    const error = (body as { error?: { code?: string; message?: string } } | null)?.error;
    throw new ApiError(response.status, error?.code ?? "http_error", error?.message ?? `Errore HTTP ${response.status}`);
  }
  return body as T;
}

export const api = {
  me: () =>
    request<{ authenticated: boolean; operator: string | null; loginConfigured: boolean }>("/api/auth/me"),
  login: (password: string, operator: string) =>
    request<{ ok: true; operator: string; expiresAt: number }>("/api/auth/login", {
      method: "POST",
      body: JSON.stringify({ password, operator }),
    }),
  logout: () => request<{ ok: true }>("/api/auth/logout", { method: "POST", body: "{}" }),
  config: () => request<{ config: PublicConfig }>("/api/config"),
  claim: (code: string, name: string, slot: number) =>
    request<{ camera: CameraView; warning: string | null }>("/api/cameras/claim", {
      method: "POST",
      body: JSON.stringify({ code, name, slot }),
    }),
  updateCamera: (id: string, patch: { name?: string; slot?: number }) =>
    request<{ camera: CameraView }>(`/api/cameras/${encodeURIComponent(id)}`, {
      method: "PATCH",
      body: JSON.stringify(patch),
    }),
  revoke: (id: string) =>
    request<{ cloudflareAction: string }>(`/api/cameras/${encodeURIComponent(id)}`, { method: "DELETE" }),
  playback: (id: string) => request<PlaybackInfo>(`/api/cameras/${encodeURIComponent(id)}/playback`),
  liveInput: (id: string, action: "create" | "enable" | "disable" | "rotate" | "refresh") =>
    request<{ message: string; camera: CameraView }>(`/api/cameras/${encodeURIComponent(id)}/live-input`, {
      method: "POST",
      body: JSON.stringify({ action }),
    }),
  events: (cameraId?: string) =>
    request<{ events: EventView[] }>(`/api/events?limit=200${cameraId ? `&cameraId=${encodeURIComponent(cameraId)}` : ""}`),
};
