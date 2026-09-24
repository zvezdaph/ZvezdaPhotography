import { ReconnectPolicy } from "./reconnect";

export interface SocketHandlers {
  onMessage: (message: Record<string, unknown>) => void;
  onStatus: (status: "connecting" | "online" | "offline") => void;
  /** Called when the server closes because the session is no longer valid. */
  onUnauthorized: () => void;
}

const PING_INTERVAL_MS = 20_000;
const PONG_TIMEOUT_MS = 45_000;

/**
 * WebSocket to /ws/control with automatic reconnection (exponential backoff)
 * and an application level heartbeat that detects half-open connections.
 */
export class ControlSocket {
  private ws: WebSocket | null = null;
  private readonly policy = new ReconnectPolicy();
  private reconnectTimer: ReturnType<typeof setTimeout> | null = null;
  private pingTimer: ReturnType<typeof setInterval> | null = null;
  private lastMessageAt = 0;
  private stopped = true;

  constructor(
    private readonly handlers: SocketHandlers,
    private readonly url: string = ControlSocket.defaultUrl(),
  ) {}

  static defaultUrl(): string {
    const { protocol, host } = window.location;
    return `${protocol === "https:" ? "wss:" : "ws:"}//${host}/ws/control`;
  }

  start(): void {
    this.stopped = false;
    this.connect();
  }

  stop(): void {
    this.stopped = true;
    if (this.reconnectTimer) clearTimeout(this.reconnectTimer);
    this.reconnectTimer = null;
    this.clearPing();
    this.ws?.close(1000, "bye");
    this.ws = null;
  }

  send(message: unknown): boolean {
    if (!this.ws || this.ws.readyState !== WebSocket.OPEN) return false;
    this.ws.send(JSON.stringify(message));
    return true;
  }

  get connected(): boolean {
    return this.ws?.readyState === WebSocket.OPEN;
  }

  /** Forces an immediate reconnection (e.g. after the network came back). */
  reconnectNow(): void {
    if (this.stopped) return;
    this.policy.reset();
    this.ws?.close(4000, "reconnect");
  }

  private connect(): void {
    if (this.stopped) return;
    this.handlers.onStatus("connecting");
    let ws: WebSocket;
    try {
      ws = new WebSocket(this.url);
    } catch {
      this.scheduleReconnect();
      return;
    }
    this.ws = ws;
    ws.onopen = () => {
      this.policy.reset();
      this.lastMessageAt = Date.now();
      this.handlers.onStatus("online");
      this.startPing();
    };
    ws.onmessage = (event) => {
      this.lastMessageAt = Date.now();
      try {
        const data = JSON.parse(String(event.data));
        if (data && typeof data === "object") this.handlers.onMessage(data as Record<string, unknown>);
      } catch {
        // ignore malformed frames
      }
    };
    ws.onclose = (event) => {
      if (this.ws === ws) this.ws = null;
      this.clearPing();
      if (this.stopped) return;
      this.handlers.onStatus("offline");
      if (event.code === 4003 || event.code === 1008) {
        this.handlers.onUnauthorized();
        return;
      }
      this.scheduleReconnect();
    };
    ws.onerror = () => {
      // onclose follows and handles reconnection
    };
  }

  private scheduleReconnect(): void {
    if (this.stopped || this.reconnectTimer) return;
    const delay = this.policy.nextDelayMs();
    this.reconnectTimer = setTimeout(() => {
      this.reconnectTimer = null;
      this.connect();
    }, delay);
  }

  private startPing(): void {
    this.clearPing();
    this.pingTimer = setInterval(() => {
      if (Date.now() - this.lastMessageAt > PONG_TIMEOUT_MS) {
        this.ws?.close(4000, "heartbeat timeout");
        return;
      }
      this.send({ v: 1, type: "ping", t: Date.now() });
    }, PING_INTERVAL_MS);
  }

  private clearPing(): void {
    if (this.pingTimer) clearInterval(this.pingTimer);
    this.pingTimer = null;
  }
}
