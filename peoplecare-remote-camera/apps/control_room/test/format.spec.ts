import { describe, expect, it } from "vitest";
import { cameraTitle, formatAgo, formatBytes, formatDuration, formatKbps, slotLabel } from "../src/format";

describe("formatting", () => {
  it("formats slots, bitrates, durations and sizes", () => {
    expect(slotLabel(1)).toBe("CAM 01");
    expect(slotLabel(12)).toBe("CAM 12");
    expect(formatKbps(850)).toBe("850 kbps");
    expect(formatKbps(4870)).toBe("4.9 Mbps");
    expect(formatKbps(null)).toBe("—");
    expect(formatDuration(754)).toBe("12:34");
    expect(formatDuration(3723)).toBe("1:02:03");
    expect(formatBytes(25_000_000_000)).toBe("23.3 GB");
    expect(formatAgo(1000, 1000 + 125_000)).toBe("2 min fa");
  });
});

describe("cameraTitle", () => {
  it("does not repeat the slot when the name already starts with it", () => {
    expect(cameraTitle(1, "CAM 01 - SALA")).toBe("CAM 01 - SALA");
    expect(cameraTitle(2, "Palco")).toBe("CAM 02 Palco");
    expect(cameraTitle(3, "cam 03 mobile")).toBe("cam 03 mobile");
  });
});
