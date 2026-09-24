import { describe, expect, it } from "vitest";
import { ReconnectPolicy } from "../src/reconnect";

describe("reconnect policy", () => {
  it("grows exponentially up to the cap", () => {
    const policy = new ReconnectPolicy({ initialMs: 1000, maxMs: 30_000, multiplier: 2, jitter: 0 }, () => 0);
    expect([1, 2, 3, 4, 5, 6, 7].map(() => policy.nextDelayMs())).toEqual([1000, 2000, 4000, 8000, 16000, 30000, 30000]);
    expect(policy.attempts).toBe(7);
    policy.reset();
    expect(policy.nextDelayMs()).toBe(1000);
  });

  it("applies jitter within [delay/2, delay]", () => {
    const low = new ReconnectPolicy({ initialMs: 1000, maxMs: 30_000, multiplier: 2, jitter: 0.5 }, () => 0.999);
    const high = new ReconnectPolicy({ initialMs: 1000, maxMs: 30_000, multiplier: 2, jitter: 0.5 }, () => 0);
    expect(low.nextDelayMs()).toBe(501);
    expect(high.nextDelayMs()).toBe(1000);
  });
});
