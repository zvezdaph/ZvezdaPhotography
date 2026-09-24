import { describe, expect, it } from "vitest";
import { connectionQuality, controlAvailability, tallyState } from "../src/controls";
import { camera } from "./fixtures";

describe("control availability", () => {
  it("disables everything when the phone is offline", () => {
    const c = controlAvailability(camera({ online: false }));
    expect(c.start).toBe(false);
    expect(c.torch).toBe(false);
    expect(c.zoom.enabled).toBe(false);
    expect(c.reasons.all).toContain("non connesso");
  });

  it("enables START only when idle and ready", () => {
    const idle = controlAvailability(camera());
    expect(idle.start).toBe(true);
    expect(idle.pause).toBe(false);
    expect(idle.stop).toBe(false);
    const live = controlAvailability(camera({ state: { ...camera().state!, streamStatus: "live" } }));
    expect(live.start).toBe(false);
    expect(live.pause).toBe(true);
    expect(live.stop).toBe(true);
    const paused = controlAvailability(camera({ state: { ...camera().state!, streamStatus: "live", paused: true } }));
    expect(paused.pause).toBe(false);
    expect(paused.resume).toBe(true);
  });

  it("uses the capabilities of the active lens", () => {
    const back = controlAvailability(camera());
    expect(back.torch).toBe(true);
    expect(back.focusPoint).toBe(true);
    expect(back.front).toBe(true);
    expect(back.back).toBe(false);
    const front = controlAvailability(camera({ state: { ...camera().state!, facing: "front" } }));
    expect(front.torch).toBe(false);
    expect(front.focusPoint).toBe(false);
    expect(front.reasons.torch).toBeDefined();
    expect(front.fps.filter((f) => f.enabled).map((f) => f.value)).toEqual([25, 30]);
    expect(back.fps.filter((f) => f.enabled).map((f) => f.value)).toEqual([25, 30, 60]);
  });

  it("never enables controls without reported capabilities", () => {
    const c = controlAvailability(camera({ capabilities: null }));
    expect(c.torch).toBe(false);
    expect(c.zoom.enabled).toBe(false);
    expect(c.resolutions.every((r) => !r.enabled)).toBe(true);
  });
});

describe("tally and quality", () => {
  it("shows LIVE only when the phone reports live", () => {
    expect(tallyState(camera())).toBe("ready");
    expect(tallyState(camera({ state: { ...camera().state!, streamStatus: "live" } }))).toBe("live");
    expect(tallyState(camera({ state: { ...camera().state!, streamStatus: "live", paused: true } }))).toBe("paused");
    expect(tallyState(camera({ state: { ...camera().state!, streamStatus: "reconnecting" } }))).toBe("reconnecting");
    expect(tallyState(camera({ online: false, state: { ...camera().state!, streamStatus: "live" } }))).toBe("offline");
  });

  it("derives connection quality from delivered bitrate and queue", () => {
    const base = camera();
    const live = { ...base.state!, streamStatus: "live" as const, targetBitrateKbps: 5000 };
    expect(connectionQuality(camera({ state: live, telemetry: { ...base.telemetry!, bitrateKbps: 4900, queuePercent: 1 } }))).toBe("good");
    expect(connectionQuality(camera({ state: live, telemetry: { ...base.telemetry!, bitrateKbps: 3500, queuePercent: 1 } }))).toBe("fair");
    expect(connectionQuality(camera({ state: live, telemetry: { ...base.telemetry!, bitrateKbps: 4900, queuePercent: 80 } }))).toBe("poor");
    expect(connectionQuality(camera())).toBe("unknown");
  });
});
