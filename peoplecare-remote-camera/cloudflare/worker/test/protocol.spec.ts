import { describe, expect, it } from "vitest";
import {
  COMMANDS,
  formatPairingCode,
  isValidPairingCode,
  normalizePairingCode,
  parsePairingQr,
  sanitizeCapabilities,
  sanitizeState,
  sanitizeTelemetry,
  validateAck,
  validateCommandRequest,
  validateCommandValue,
} from "../src/shared/protocol";
import commandRequest from "../../../docs/protocol-fixtures/command_request.json";
import ackReceived from "../../../docs/protocol-fixtures/ack_received.json";
import ackOk from "../../../docs/protocol-fixtures/ack_completed_ok.json";
import ackError from "../../../docs/protocol-fixtures/ack_completed_error.json";
import hello from "../../../docs/protocol-fixtures/hello.json";
import telemetry from "../../../docs/protocol-fixtures/telemetry.json";
import invalidRequests from "../../../docs/protocol-fixtures/invalid_command_requests.json";

const NOW = 1790000000000;

describe("command requests", () => {
  it("accepts the golden command request", () => {
    const result = validateCommandRequest(commandRequest, NOW);
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.value.command).toBe("set_zoom");
      expect(result.value.value).toBe(2.5);
    }
  });

  it.each(invalidRequests.map((entry) => [entry.reason, entry.message] as const))("rejects: %s", (_reason, message) => {
    expect(validateCommandRequest(message, NOW).ok).toBe(false);
  });

  it("rejects commands issued too far in the future (clock skew / replay)", () => {
    expect(validateCommandRequest({ ...commandRequest, issuedAt: NOW + 10 * 60_000 }, NOW).ok).toBe(false);
  });

  it("normalizes values", () => {
    expect(validateCommandValue("set_zoom", 2.345)).toEqual({ ok: true, value: 2.35 });
    expect(validateCommandValue("set_bitrate", { mode: "manual", kbps: 4999.6 })).toEqual({
      ok: true,
      value: { mode: "manual", kbps: 5000 },
    });
    expect(validateCommandValue("set_bitrate", { mode: "auto" })).toEqual({ ok: true, value: { mode: "auto" } });
    expect(validateCommandValue("pause", undefined)).toEqual({ ok: true, value: null });
    expect(validateCommandValue("focus_point", { x: 0.25, y: 0.75, extra: 1 })).toEqual({
      ok: true,
      value: { x: 0.25, y: 0.75 },
    });
  });

  it("has a validator for every command", () => {
    const samples: Record<string, unknown> = {
      switch_camera: "front",
      set_zoom: 1,
      set_audio_enabled: true,
      set_video_enabled: false,
      set_torch: true,
      set_autofocus: true,
      focus_point: { x: 0.5, y: 0.5 },
      set_exposure: 2,
      set_resolution: "720p",
      set_fps: 25,
      set_bitrate: { mode: "manual", kbps: 3000 },
      set_preset: "standard",
      set_record: true,
    };
    for (const command of COMMANDS) {
      expect(validateCommandValue(command, samples[command] ?? null).ok, command).toBe(true);
    }
  });
});

describe("acks", () => {
  it("accepts golden acks", () => {
    expect(validateAck(ackReceived).ok).toBe(true);
    expect(validateAck(ackOk).ok).toBe(true);
    const failed = validateAck(ackError);
    expect(failed.ok).toBe(true);
    if (failed.ok) expect(failed.value.error?.code).toBe("unsupported");
  });

  it("requires an error on failed completion", () => {
    expect(validateAck({ ...ackError, error: null }).ok).toBe(false);
  });

  it("rejects unknown stages", () => {
    expect(validateAck({ ...ackOk, stage: "done" }).ok).toBe(false);
  });
});

describe("sanitizers", () => {
  it("keeps the golden hello capabilities and state", () => {
    const caps = sanitizeCapabilities(hello.capabilities);
    expect(caps?.facings.back?.torch).toBe(true);
    expect(caps?.facings.front?.torch).toBe(false);
    expect(caps?.facings.back?.fps["1080p"]).toEqual([25, 30, 60]);
    expect(caps?.resolutions).toEqual(["720p", "1080p"]);
    const state = sanitizeState(hello.state);
    expect(state?.streamStatus).toBe("idle");
    expect(state?.facing).toBe("back");
  });

  it("clamps and drops unexpected telemetry fields", () => {
    const t = sanitizeTelemetry({ ...telemetry.telemetry, evil: "<script>", battery: { percent: 500, charging: "yes" } }, NOW);
    expect(t).not.toBeNull();
    expect((t as unknown as Record<string, unknown>).evil).toBeUndefined();
    expect(t?.battery.percent).toBe(100);
    expect(t?.battery.charging).toBe(false);
    expect(t?.network.type).toBe("cellular");
    expect(t?.recentErrors).toHaveLength(1);
  });
});

describe("pairing codes", () => {
  it("normalizes human input", () => {
    expect(normalizePairingCode("k7f2-9qxd")).toBe("K7F29QXD");
    expect(normalizePairingCode(" ab0o 1il2 ")).toBe("AB001112");
  });

  it("validates the alphabet and length", () => {
    expect(isValidPairingCode("K7F29QXD")).toBe(true);
    expect(isValidPairingCode("K7F29QX")).toBe(false);
    expect(isValidPairingCode("K7F29QXU")).toBe(false);
    expect(formatPairingCode("K7F29QXD")).toBe("K7F2-9QXD");
  });

  it("parses QR payloads", () => {
    expect(parsePairingQr("PCRC:1:K7F2-9QXD:studio.example")).toBe("K7F29QXD");
    expect(parsePairingQr("PCRC:1:K7F29QXD")).toBe("K7F29QXD");
    expect(parsePairingQr("k7f2-9qxd")).toBe("K7F29QXD");
    expect(parsePairingQr("https://evil.example")).toBeNull();
  });
});
