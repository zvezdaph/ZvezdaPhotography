export const SESSION_COOKIE = "pcrc_session";

const API_HEADERS: Record<string, string> = {
  "Content-Type": "application/json; charset=utf-8",
  "Cache-Control": "no-store",
  "X-Content-Type-Options": "nosniff",
  "Referrer-Policy": "no-referrer",
  "X-Frame-Options": "DENY",
};

export class HttpError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    message: string,
    readonly extraHeaders: Record<string, string> = {},
  ) {
    super(message);
  }
}

export function json(body: unknown, status = 200, headers: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(body), { status, headers: { ...API_HEADERS, ...headers } });
}

export function errorResponse(err: HttpError): Response {
  return json({ ok: false, error: { code: err.code, message: err.message } }, err.status, err.extraHeaders);
}

export function withApiHeaders(response: Response): Response {
  const headers = new Headers(response.headers);
  for (const [key, value] of Object.entries(API_HEADERS)) {
    if (key === "Content-Type" && headers.has("Content-Type")) continue;
    headers.set(key, value);
  }
  return new Response(response.body, { status: response.status, statusText: response.statusText, headers });
}

/** Reads a JSON body, refusing bodies bigger than `maxBytes`. */
export async function readJson(request: Request, maxBytes = 16 * 1024): Promise<Record<string, unknown>> {
  const declared = Number(request.headers.get("Content-Length") ?? "0");
  if (declared > maxBytes) throw new HttpError(413, "payload_too_large", "Request body too large");
  const text = await request.text();
  if (text.length > maxBytes) throw new HttpError(413, "payload_too_large", "Request body too large");
  if (text.trim() === "") return {};
  let parsed: unknown;
  try {
    parsed = JSON.parse(text);
  } catch {
    throw new HttpError(400, "invalid_json", "Body is not valid JSON");
  }
  if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed)) {
    throw new HttpError(400, "invalid_json", "Body must be a JSON object");
  }
  return parsed as Record<string, unknown>;
}

export function parseCookies(header: string | null): Map<string, string> {
  const cookies = new Map<string, string>();
  if (!header) return cookies;
  for (const part of header.split(";")) {
    const index = part.indexOf("=");
    if (index <= 0) continue;
    const name = part.slice(0, index).trim();
    const value = part.slice(index + 1).trim();
    if (name) cookies.set(name, decodeURIComponent(value));
  }
  return cookies;
}

export function sessionCookie(token: string, maxAgeSec: number, secure: boolean): string {
  const parts = [
    `${SESSION_COOKIE}=${encodeURIComponent(token)}`,
    "Path=/",
    "HttpOnly",
    "SameSite=Strict",
    `Max-Age=${maxAgeSec}`,
  ];
  if (secure) parts.push("Secure");
  return parts.join("; ");
}

export function clearSessionCookie(secure: boolean): string {
  return sessionCookie("", 0, secure);
}

export function bearerToken(request: Request): string | null {
  const header = request.headers.get("Authorization");
  if (!header) return null;
  const match = /^Bearer\s+([A-Za-z0-9._~+/=-]{16,256})$/.exec(header.trim());
  return match ? match[1] : null;
}

export function clientIp(request: Request): string {
  return request.headers.get("CF-Connecting-IP") ?? request.headers.get("X-Forwarded-For")?.split(",")[0]?.trim() ?? "unknown";
}

export function isWebSocketUpgrade(request: Request): boolean {
  return request.headers.get("Upgrade")?.toLowerCase() === "websocket";
}
