import type { Env } from "./env";
import { streamApiConfigured } from "./env";
import { HttpError, clientIp, errorResponse, json, withApiHeaders } from "./lib/http";
import { APP_VERSION } from "./studio";

export { StudioDurableObject } from "./studio";

/** Public endpoints protected by the (optional) Workers Rate Limiting binding. */
const EDGE_LIMITED = new Set(["/api/auth/login", "/api/pair/start", "/api/pair/poll", "/api/webhooks/stream"]);

/** All control-plane state lives in a single Durable Object: one studio, many cameras. */
function studio(env: Env) {
  const hint = (env.DO_LOCATION_HINT ?? "weur").trim() as DurableObjectLocationHint;
  return env.STUDIO.getByName("studio", hint ? { locationHint: hint } : undefined);
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    const path = url.pathname;

    if (path === "/api/health") {
      return json({
        ok: true,
        service: "peoplecare-remote-camera",
        version: APP_VERSION,
        streamConfigured: streamApiConfigured(env),
        time: Date.now(),
      });
    }

    if (path.startsWith("/api/") || path.startsWith("/ws/")) {
      if (env.RL_PUBLIC && EDGE_LIMITED.has(path)) {
        const { success } = await env.RL_PUBLIC.limit({ key: `${path}:${clientIp(request)}` });
        if (!success) {
          return errorResponse(new HttpError(429, "rate_limited", "Troppe richieste", { "Retry-After": "60" }));
        }
      }
      const response = await studio(env).fetch(request);
      // WebSocket upgrades must be returned untouched.
      return response.status === 101 ? response : withApiHeaders(response);
    }

    if (env.ASSETS) return env.ASSETS.fetch(request);
    return new Response("Not found", { status: 404 });
  },
} satisfies ExportedHandler<Env>;
