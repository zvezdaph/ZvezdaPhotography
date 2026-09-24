import type { CameraView } from "../src/types";
import hello from "../../../docs/protocol-fixtures/hello.json";
import telemetry from "../../../docs/protocol-fixtures/telemetry.json";
import { sanitizeCapabilities, sanitizeState, sanitizeTelemetry } from "@protocol";

export function camera(overrides: Partial<CameraView> = {}): CameraView {
  return {
    id: "cam_0a1b2c3d4e5f6a7b",
    slot: 1,
    name: "CAM 01 - SALA",
    online: true,
    activated: true,
    lastSeenAt: 1790000000000,
    device: { model: "Pixel 9", appVersion: "1.0.0", osVersion: "Android 16" },
    capabilities: sanitizeCapabilities(hello.capabilities),
    state: sanitizeState(hello.state),
    telemetry: sanitizeTelemetry(telemetry.telemetry, 1790000002000),
    cloudflare: { configured: true, liveInputId: "0123456789abcdef0123456789abcdef", state: "offline", status: null, statusAt: null, error: null },
    playback: null,
    ...overrides,
  };
}
