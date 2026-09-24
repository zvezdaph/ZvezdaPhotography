import { describe, expect, it } from "vitest";
import { addPendingCommand, applyServerMessage, camerasBySlot, freeSlots, initialState, isNewerStatus, latestCommandFor } from "../src/store";
import { camera } from "./fixtures";

describe("store reducer", () => {
  it("loads a snapshot and computes the server clock offset", () => {
    const state = applyServerMessage(
      initialState(),
      { type: "snapshot", serverTime: 2_000, operator: "Mario", cameras: [camera()], events: [], commands: [], config: null },
      1_000,
    );
    expect(state.connection).toBe("online");
    expect(state.serverOffsetMs).toBe(1_000);
    expect(state.auth.operator).toBe("Mario");
    expect(Object.keys(state.cameras)).toEqual(["cam_0a1b2c3d4e5f6a7b"]);
  });

  it("applies camera updates, telemetry and removals", () => {
    let state = applyServerMessage(initialState(), { type: "snapshot", serverTime: 0, cameras: [camera()] });
    state = applyServerMessage(state, { type: "camera_update", camera: camera({ name: "CAM 01 - PALCO" }) });
    expect(state.cameras.cam_0a1b2c3d4e5f6a7b.name).toBe("CAM 01 - PALCO");
    const t = { ...state.cameras.cam_0a1b2c3d4e5f6a7b.telemetry!, bitrateKbps: 1234 };
    state = applyServerMessage(state, { type: "telemetry", cameraId: "cam_0a1b2c3d4e5f6a7b", telemetry: t });
    expect(state.cameras.cam_0a1b2c3d4e5f6a7b.telemetry?.bitrateKbps).toBe(1234);
    state = { ...state, route: { name: "camera", cameraId: "cam_0a1b2c3d4e5f6a7b" } };
    state = applyServerMessage(state, { type: "camera_removed", cameraId: "cam_0a1b2c3d4e5f6a7b" });
    expect(state.cameras).toEqual({});
    expect(state.route).toEqual({ name: "dashboard" });
  });

  it("ignores telemetry for unknown cameras and unknown message types", () => {
    const state = initialState();
    expect(applyServerMessage(state, { type: "telemetry", cameraId: "x", telemetry: {} })).toBe(state);
    expect(applyServerMessage(state, { type: "future_message" })).toBe(state);
  });

  it("tracks the command lifecycle only forward", () => {
    let state = addPendingCommand(initialState(), { commandId: "c1", cameraId: "cam", command: "pause", status: "pending", updatedAt: 1 });
    state = applyServerMessage(state, { type: "command_status", commandId: "c1", status: "received", updatedAt: 3 });
    // a late "sent" must not move the command backwards
    state = applyServerMessage(state, { type: "command_status", commandId: "c1", status: "sent", updatedAt: 2 });
    expect(state.commands.c1.status).toBe("received");
    state = applyServerMessage(state, { type: "command_status", commandId: "c1", status: "completed", result: { ok: 1 }, updatedAt: 4 });
    expect(state.commands.c1.status).toBe("completed");
    expect(state.commands.c1.command).toBe("pause");
    expect(latestCommandFor(state, "cam", "pause")?.status).toBe("completed");
  });

  it("lets a late ACK override a timeout", () => {
    expect(isNewerStatus("timeout", "completed")).toBe(true);
    expect(isNewerStatus("completed", "timeout")).toBe(false);
    expect(isNewerStatus("sent", "received")).toBe(true);
    expect(isNewerStatus("received", "sent")).toBe(false);
  });

  it("de-duplicates events and caps the log", () => {
    let state = initialState();
    for (let i = 0; i < 400; i++) {
      state = applyServerMessage(state, { type: "event", event: { id: i, ts: i, cameraId: null, level: "info", source: "t", message: `m${i}` } });
    }
    state = applyServerMessage(state, { type: "event", event: { id: 399, ts: 399, cameraId: null, level: "info", source: "t", message: "dup" } });
    expect(state.events).toHaveLength(300);
    expect(state.events.at(-1)?.message).toBe("m399");
  });

  it("sorts cameras by slot and lists free slots", () => {
    const state = applyServerMessage(initialState(), {
      type: "snapshot",
      serverTime: 0,
      cameras: [camera({ id: "cam_bbbbbbbbbbbbbbbb", slot: 3 }), camera({ id: "cam_aaaaaaaaaaaaaaaa", slot: 1 })],
    });
    expect(camerasBySlot(state).map((c) => c.slot)).toEqual([1, 3]);
    expect(freeSlots(state, 4)).toEqual([2, 4]);
  });
});
