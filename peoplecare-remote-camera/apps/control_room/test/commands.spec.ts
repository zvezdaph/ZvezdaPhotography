import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { CommandSender } from "../src/commands";
import { Store, initialState } from "../src/store";
import type { ControlSocket } from "../src/socket";

function fakeSocket(connected = true) {
  const sent: Array<Record<string, unknown>> = [];
  const socket = { send: (m: Record<string, unknown>) => (connected ? (sent.push(m), true) : false) } as unknown as ControlSocket;
  return { socket, sent };
}

describe("command sender", () => {
  beforeEach(() => vi.useFakeTimers());
  afterEach(() => vi.useRealTimers());

  it("sends validated commands with a unique id and server based timestamp", () => {
    const store = new Store({ ...initialState(), serverOffsetMs: 5000 });
    const { socket, sent } = fakeSocket();
    const sender = new CommandSender(store, socket);
    vi.setSystemTime(1_000_000);
    const a = sender.send("cam_0a1b2c3d4e5f6a7b", "set_zoom", 2);
    const b = sender.send("cam_0a1b2c3d4e5f6a7b", "set_zoom", 2);
    expect(a).not.toBe(b);
    expect(sent[0]).toMatchObject({ v: 1, type: "command", command: "set_zoom", value: 2, issuedAt: 1_005_000 });
    expect(store.get().commands[a as string].status).toBe("pending");
  });

  it("refuses invalid values locally", () => {
    const store = new Store();
    const { socket, sent } = fakeSocket();
    const sender = new CommandSender(store, socket);
    expect(sender.send("cam_0a1b2c3d4e5f6a7b", "set_fps", 24)).toBeNull();
    expect(sent).toHaveLength(0);
    expect(store.get().toasts[0].level).toBe("error");
  });

  it("does not pretend success when the socket is down", () => {
    const store = new Store();
    const { socket } = fakeSocket(false);
    const sender = new CommandSender(store, socket);
    expect(sender.send("cam_0a1b2c3d4e5f6a7b", "pause")).toBeNull();
    expect(Object.keys(store.get().commands)).toHaveLength(0);
  });

  it("throttles slider commands and always delivers the last value", () => {
    const store = new Store();
    const { socket, sent } = fakeSocket();
    const sender = new CommandSender(store, socket);
    vi.setSystemTime(10_000);
    for (const z of [1.1, 1.2, 1.3, 1.4]) sender.sendThrottled("cam_0a1b2c3d4e5f6a7b", "set_zoom", z, 150);
    expect(sent.map((m) => m.value)).toEqual([1.1]);
    vi.advanceTimersByTime(200);
    expect(sent.map((m) => m.value)).toEqual([1.1, 1.4]);
  });
});
