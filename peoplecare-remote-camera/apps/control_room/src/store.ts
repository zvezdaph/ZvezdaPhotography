import type { CameraView, CommandLifecycle, CommandView, EventView, PublicConfig, Telemetry } from "./types";

export type Route = { name: "dashboard" } | { name: "camera"; cameraId: string };

export interface Toast {
  id: number;
  level: "info" | "success" | "warning" | "error";
  message: string;
}

export interface AppState {
  auth: { status: "unknown" | "anonymous" | "authenticated"; operator: string | null; loginConfigured: boolean };
  connection: "idle" | "connecting" | "online" | "offline";
  /** serverTime - Date.now(), measured on snapshot and pong. */
  serverOffsetMs: number;
  config: PublicConfig | null;
  cameras: Record<string, CameraView>;
  events: EventView[];
  commands: Record<string, CommandView>;
  route: Route;
  toasts: Toast[];
}

export const MAX_EVENTS = 300;
export const MAX_COMMANDS = 200;

export function initialState(): AppState {
  return {
    auth: { status: "unknown", operator: null, loginConfigured: true },
    connection: "idle",
    serverOffsetMs: 0,
    config: null,
    cameras: {},
    events: [],
    commands: {},
    route: { name: "dashboard" },
    toasts: [],
  };
}

type ServerMessage = Record<string, unknown> & { type?: unknown };

function trimCommands(commands: Record<string, CommandView>): Record<string, CommandView> {
  const entries = Object.values(commands);
  if (entries.length <= MAX_COMMANDS) return commands;
  entries.sort((a, b) => b.updatedAt - a.updatedAt);
  return Object.fromEntries(entries.slice(0, MAX_COMMANDS).map((c) => [c.commandId, c]));
}

const FINAL: CommandLifecycle[] = ["completed", "failed", "rejected", "timeout"];

/** Returns true when `next` may replace `current` (statuses only move forward). */
export function isNewerStatus(current: CommandLifecycle | undefined, next: CommandLifecycle): boolean {
  if (!current) return true;
  if (FINAL.includes(current)) {
    // A late ACK may still turn a timeout into completed/failed.
    return current === "timeout" && (next === "completed" || next === "failed");
  }
  const order: CommandLifecycle[] = ["pending", "sent", "received"];
  if (FINAL.includes(next)) return true;
  return order.indexOf(next) > order.indexOf(current);
}

/**
 * Pure reducer applying one control-plane message to the state.
 * Unknown messages are ignored so that newer servers do not break older UIs.
 */
export function applyServerMessage(state: AppState, message: ServerMessage, now = Date.now()): AppState {
  switch (message.type) {
    case "snapshot": {
      const cameras: Record<string, CameraView> = {};
      for (const camera of (message.cameras as CameraView[]) ?? []) cameras[camera.id] = camera;
      const commands: Record<string, CommandView> = { ...state.commands };
      for (const command of (message.commands as CommandView[]) ?? []) commands[command.commandId] = command;
      return {
        ...state,
        connection: "online",
        serverOffsetMs: typeof message.serverTime === "number" ? message.serverTime - now : state.serverOffsetMs,
        config: (message.config as PublicConfig) ?? state.config,
        cameras,
        events: ((message.events as EventView[]) ?? []).slice(-MAX_EVENTS),
        commands: trimCommands(commands),
        auth: { ...state.auth, status: "authenticated", operator: (message.operator as string) ?? state.auth.operator },
      };
    }
    case "camera_update": {
      const camera = message.camera as CameraView | undefined;
      if (!camera?.id) return state;
      return { ...state, cameras: { ...state.cameras, [camera.id]: camera } };
    }
    case "camera_removed": {
      const id = message.cameraId as string;
      if (!state.cameras[id]) return state;
      const cameras = { ...state.cameras };
      delete cameras[id];
      const route: Route = state.route.name === "camera" && state.route.cameraId === id ? { name: "dashboard" } : state.route;
      return { ...state, cameras, route };
    }
    case "telemetry": {
      const id = message.cameraId as string;
      const camera = state.cameras[id];
      if (!camera) return state;
      return { ...state, cameras: { ...state.cameras, [id]: { ...camera, telemetry: message.telemetry as Telemetry } } };
    }
    case "event": {
      const event = message.event as EventView | undefined;
      if (!event) return state;
      if (state.events.some((e) => e.id === event.id)) return state;
      return { ...state, events: [...state.events, event].slice(-MAX_EVENTS) };
    }
    case "command_status": {
      const commandId = message.commandId as string | null;
      if (!commandId) return state;
      const next = message.status as CommandLifecycle;
      const current = state.commands[commandId];
      if (!isNewerStatus(current?.status, next)) return state;
      const view: CommandView = {
        commandId,
        cameraId: (message.cameraId as string | null) ?? current?.cameraId ?? null,
        command: (message.command as string | null) ?? current?.command ?? null,
        value: message.value ?? current?.value,
        issuedBy: (message.issuedBy as string | undefined) ?? current?.issuedBy,
        status: next,
        result: (message.result as Record<string, unknown> | null | undefined) ?? current?.result ?? null,
        error: (message.error as CommandView["error"]) ?? null,
        updatedAt: typeof message.updatedAt === "number" ? message.updatedAt : now,
      };
      return { ...state, commands: trimCommands({ ...state.commands, [commandId]: view }) };
    }
    case "pong":
      if (typeof message.serverTime === "number") return { ...state, serverOffsetMs: message.serverTime - now };
      return state;
    default:
      return state;
  }
}

/** Registers a command sent by this UI before the server confirms it. */
export function addPendingCommand(state: AppState, command: CommandView): AppState {
  return { ...state, commands: trimCommands({ ...state.commands, [command.commandId]: command }) };
}

export function camerasBySlot(state: AppState): CameraView[] {
  return Object.values(state.cameras).sort((a, b) => a.slot - b.slot || a.name.localeCompare(b.name));
}

export function freeSlots(state: AppState, max = 16): number[] {
  const used = new Set(Object.values(state.cameras).map((c) => c.slot));
  const free: number[] = [];
  for (let slot = 1; slot <= max; slot++) if (!used.has(slot)) free.push(slot);
  return free;
}

export function latestCommandFor(state: AppState, cameraId: string, command: string): CommandView | null {
  let latest: CommandView | null = null;
  for (const c of Object.values(state.commands)) {
    if (c.cameraId === cameraId && c.command === command && (!latest || c.updatedAt > latest.updatedAt)) latest = c;
  }
  return latest;
}

// ---------------------------------------------------------------------------
// Tiny observable store with a Preact hook.
// ---------------------------------------------------------------------------

type Listener = () => void;

export class Store {
  private state: AppState;
  private readonly listeners = new Set<Listener>();
  private toastId = 0;

  constructor(initial: AppState = initialState()) {
    this.state = initial;
  }

  get(): AppState {
    return this.state;
  }

  set(update: (state: AppState) => AppState): void {
    const next = update(this.state);
    if (next === this.state) return;
    this.state = next;
    for (const listener of this.listeners) listener();
  }

  subscribe(listener: Listener): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  toast(level: Toast["level"], message: string, timeoutMs = 5000): void {
    const id = ++this.toastId;
    this.set((s) => ({ ...s, toasts: [...s.toasts.slice(-4), { id, level, message }] }));
    setTimeout(() => this.set((s) => ({ ...s, toasts: s.toasts.filter((t) => t.id !== id) })), timeoutMs);
  }
}
