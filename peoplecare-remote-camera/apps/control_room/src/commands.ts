import type { CommandName } from "@protocol";
import { validateCommandValue } from "@protocol";
import type { Store } from "./store";
import { addPendingCommand } from "./store";
import type { ControlSocket } from "./socket";
import { commandLabel } from "./format";

export function newCommandId(): string {
  if (typeof crypto !== "undefined" && typeof crypto.randomUUID === "function") return crypto.randomUUID();
  const bytes = new Uint8Array(16);
  crypto.getRandomValues(bytes);
  return Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");
}

/**
 * Sends commands to a camera through the control plane.
 * Each command gets a unique id and the server time based issue timestamp
 * (so that a wrong PC clock does not make commands look like replays).
 * The UI only shows success when the phone ACK arrives.
 */
export class CommandSender {
  private readonly throttles = new Map<string, { timer: ReturnType<typeof setTimeout> | null; last: number; pending: unknown }>();

  constructor(
    private readonly store: Store,
    private readonly socket: ControlSocket,
  ) {}

  send(cameraId: string, command: CommandName, value?: unknown): string | null {
    const validated = validateCommandValue(command, value);
    if (!validated.ok) {
      this.store.toast("error", `${commandLabel(command)}: ${validated.error}`);
      return null;
    }
    const commandId = newCommandId();
    const issuedAt = Date.now() + this.store.get().serverOffsetMs;
    const message = { v: 1, type: "command", commandId, cameraId, command, value: validated.value, issuedAt };
    if (!this.socket.send(message)) {
      this.store.toast("error", "Regia non connessa al server: comando non inviato");
      return null;
    }
    this.store.set((s) =>
      addPendingCommand(s, {
        commandId,
        cameraId,
        command,
        value: validated.value,
        status: "pending",
        updatedAt: Date.now(),
      }),
    );
    return commandId;
  }

  /**
   * For sliders (zoom, exposure): sends at most one command every `intervalMs`,
   * always delivering the last value.
   */
  sendThrottled(cameraId: string, command: CommandName, value: unknown, intervalMs = 150): void {
    const key = `${cameraId}:${command}`;
    const entry = this.throttles.get(key) ?? { timer: null, last: 0, pending: undefined };
    this.throttles.set(key, entry);
    const now = Date.now();
    const wait = entry.last + intervalMs - now;
    if (wait <= 0 && !entry.timer) {
      entry.last = now;
      this.send(cameraId, command, value);
      return;
    }
    entry.pending = value;
    if (!entry.timer) {
      entry.timer = setTimeout(() => {
        entry.timer = null;
        entry.last = Date.now();
        this.send(cameraId, command, entry.pending);
      }, Math.max(0, wait));
    }
  }
}
