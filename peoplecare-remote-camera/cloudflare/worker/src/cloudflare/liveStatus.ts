import type { CloudflareIngestState } from "../shared/protocol";
import { isRecord } from "../shared/protocol";

/**
 * Connection states documented for a live input:
 * connected, reconnected, reconnecting, client_disconnect, ttl_exceeded,
 * failed_to_connect, failed_to_reconnect, new_configuration_accepted, or null.
 *
 * The API schema documents `status` as one of those strings. Some API
 * responses wrap it in an object ({ current: { state | reason } }); both
 * shapes are accepted so the control room never breaks on either.
 */
export function rawLiveInputStatus(status: unknown): string | null {
  if (typeof status === "string") return status;
  if (isRecord(status)) {
    const current = isRecord(status.current) ? status.current : status;
    for (const key of ["reason", "state"]) {
      const value = current[key];
      if (typeof value === "string" && value.length > 0) return value;
    }
  }
  return null;
}

export function mapLiveInputStatus(raw: string | null): CloudflareIngestState {
  if (raw === null) return "offline";
  switch (raw.toLowerCase()) {
    case "connected":
    case "reconnected":
    case "new_configuration_accepted":
    case "live_input.connected":
      return "live";
    case "reconnecting":
      return "reconnecting";
    case "client_disconnect":
    case "ttl_exceeded":
    case "disconnected":
    case "live_input.disconnected":
      return "offline";
    case "failed_to_connect":
    case "failed_to_reconnect":
    case "errored":
    case "live_input.errored":
      return "error";
    default:
      return "unknown";
  }
}

export interface LiveWebhookEvent {
  inputId: string;
  eventType: string;
  state: CloudflareIngestState;
  updatedAt: number;
  errorCode?: string;
  errorMessage?: string;
}

/** Parses the payload of a "Stream Live Input" notification webhook. */
export function parseLiveWebhook(body: unknown): LiveWebhookEvent | null {
  if (!isRecord(body) || !isRecord(body.data)) return null;
  const data = body.data;
  const inputId = data.input_id;
  const eventType = data.event_type;
  if (typeof inputId !== "string" || !/^[a-z0-9]{8,64}$/i.test(inputId)) return null;
  if (typeof eventType !== "string" || !eventType.startsWith("live_input.")) return null;
  const parsedTime = typeof data.updated_at === "string" ? Date.parse(data.updated_at) : NaN;
  const event: LiveWebhookEvent = {
    inputId,
    eventType,
    state: mapLiveInputStatus(eventType),
    updatedAt: Number.isFinite(parsedTime) ? parsedTime : Date.now(),
  };
  const errored = isRecord(data.live_input_errored) ? data.live_input_errored : null;
  if (errored && isRecord(errored.error)) {
    if (typeof errored.error.code === "string") event.errorCode = errored.error.code.slice(0, 64);
    if (typeof errored.error.message === "string") event.errorMessage = errored.error.message.slice(0, 300);
  }
  return event;
}
