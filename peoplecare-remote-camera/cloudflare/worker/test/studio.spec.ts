import { env, runDurableObjectAlarm, runInDurableObject } from "cloudflare:test";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import hello from "../../../docs/protocol-fixtures/hello.json";
import telemetryFixture from "../../../docs/protocol-fixtures/telemetry.json";
import { FakeStreamApi, ORIGIN, PASSWORD, api, login, nextIp, openControl, openDevice, pairCamera, uuid } from "./helpers";

let fake: FakeStreamApi;
let slotCounter = 0;
function nextSlot(): number {
  slotCounter = (slotCounter % 16) + 1;
  return slotCounter;
}

beforeEach(() => {
  fake = new FakeStreamApi();
  fake.install();
});

afterEach(async () => {
  // Revoke every camera left by a test so that slots are free again
  // (while the Cloudflare API mock is still installed).
  const cookie = await login("cleanup");
  const list = (await (await api("/api/cameras", { cookie })).json()) as { cameras: Array<{ id: string }> };
  for (const camera of list.cameras) await api(`/api/cameras/${camera.id}`, { method: "DELETE", cookie });
  vi.restoreAllMocks();
});

describe("health and auth", () => {
  it("exposes a health endpoint without secrets", async () => {
    const response = await api("/api/health", { origin: null });
    expect(response.status).toBe(200);
    const body = (await response.json()) as Record<string, unknown>;
    expect(body.ok).toBe(true);
    expect(body.streamConfigured).toBe(true);
    expect(JSON.stringify(body)).not.toContain("test-api-token");
    expect(response.headers.get("Cache-Control")).toBe("no-store");
  });

  it("rejects wrong passwords and requests without a valid Origin", async () => {
    expect((await api("/api/auth/login", { body: { password: "wrong-password-000" } })).status).toBe(401);
    expect((await api("/api/auth/login", { body: { password: PASSWORD }, origin: null })).status).toBe(403);
    expect((await api("/api/auth/login", { body: { password: PASSWORD }, origin: "https://evil.example" })).status).toBe(403);
  });

  it("creates an HttpOnly, SameSite=Strict session cookie", async () => {
    const response = await api("/api/auth/login", { body: { password: PASSWORD, operator: "Mario" } });
    expect(response.status).toBe(200);
    const cookie = response.headers.get("Set-Cookie") ?? "";
    expect(cookie).toContain("HttpOnly");
    expect(cookie).toContain("SameSite=Strict");
    expect(cookie).toContain("Secure");
    const session = `pcrc_session=${/pcrc_session=([^;]+)/.exec(cookie)?.[1]}`;
    const me = (await (await api("/api/auth/me", { cookie: session })).json()) as { authenticated: boolean; operator: string };
    expect(me).toMatchObject({ authenticated: true, operator: "Mario" });
    expect((await api("/api/cameras", { cookie: "pcrc_session=forged-session-token-xxxxxxxx" })).status).toBe(401);
  });

  it("rate limits password guessing per IP", async () => {
    const ip = nextIp();
    const statuses: number[] = [];
    for (let i = 0; i < 11; i++) {
      statuses.push((await api("/api/auth/login", { body: { password: `guess-${i}-xxxxxxx` }, ip })).status);
    }
    expect(statuses.slice(0, 10).every((s) => s === 401)).toBe(true);
    expect(statuses[10]).toBe(429);
  });

  it("refuses control WebSockets without session or from another origin", async () => {
    const noSession = await api("/ws/control", { headers: { Upgrade: "websocket" } });
    expect(noSession.status).toBe(401);
    const cookie = await login();
    const badOrigin = await api("/ws/control", { headers: { Upgrade: "websocket" }, cookie, origin: "https://evil.example" });
    expect(badOrigin.status).toBe(403);
  });
});

describe("pairing", () => {
  it("pairs a phone with a one-time code and creates its Cloudflare live input", async () => {
    const cookie = await login();
    const control = await openControl(cookie);
    await control.nextType("snapshot");
    const slot = nextSlot();
    const { cameraId, deviceToken } = await pairCamera(cookie, "CAM TEST - SALA", slot);
    expect(deviceToken.length).toBeGreaterThanOrEqual(40);

    const create = fake.calls.find((c) => c.method === "POST" && c.path === "");
    expect(create).toBeDefined();
    expect((create?.body as { recording: { mode: string } }).recording.mode).toBe("automatic");

    const device = await openDevice(deviceToken);
    const welcome = await device.nextType("welcome");
    expect(welcome).toMatchObject({ v: 1, cameraId, cameraName: "CAM TEST - SALA", slot });
    expect(typeof welcome.serverTime).toBe("number");

    const update = await control.next((m) => m.type === "camera_update" && (m.camera as { online: boolean }).online === true);
    expect((update.camera as { id: string }).id).toBe(cameraId);

    // The pairing is consumed once the phone connected: polling again gives nothing.
    device.close();
    control.close();
  });

  it("rejects unknown codes and taken slots", async () => {
    const cookie = await login();
    const bad = await api("/api/cameras/claim", { body: { code: "ZZZZ-ZZZZ", name: "X", slot: 1 }, cookie });
    expect(bad.status).toBe(404);
    const invalid = await api("/api/cameras/claim", { body: { code: "ÀÀ", name: "X", slot: 1 }, cookie });
    expect(invalid.status).toBe(400);
    const slot = nextSlot();
    await pairCamera(cookie, "CAM A", slot);
    const start = (await (await api("/api/pair/start", { body: { deviceName: "B" }, origin: null })).json()) as { code: string };
    const taken = await api("/api/cameras/claim", { body: { code: start.code, name: "CAM B", slot }, cookie });
    expect(taken.status).toBe(409);
  });

  it("does not deliver the device token before the claim and hides the pairing from others", async () => {
    const start = (await (await api("/api/pair/start", { body: { deviceName: "Phone" }, origin: null })).json()) as {
      pairingId: string;
      pollToken: string;
    };
    const pending = await api("/api/pair/poll", {
      body: { pairingId: start.pairingId },
      headers: { Authorization: `Bearer ${start.pollToken}` },
      origin: null,
    });
    expect(((await pending.json()) as { status: string }).status).toBe("pending");
    const stolen = await api("/api/pair/poll", {
      body: { pairingId: start.pairingId },
      headers: { Authorization: "Bearer wrong-poll-token-00000000000000" },
      origin: null,
    });
    expect(stolen.status).toBe(404);
  });

  it("lets the phone probe its token without upgrading (401 revoked vs 426 valid)", async () => {
    const cookie = await login();
    const { deviceToken } = await pairCamera(cookie, "CAM PROBE", nextSlot());
    const valid = await api("/ws/device", { headers: { Authorization: `Bearer ${deviceToken}` }, origin: null });
    expect(valid.status).toBe(426);
    const invalid = await api("/ws/device", { headers: { Authorization: "Bearer not-a-valid-device-token-000000000" }, origin: null });
    expect(invalid.status).toBe(401);
  });

  it("rejects device sockets with unknown tokens", async () => {
    const response = await api("/ws/device", {
      headers: { Upgrade: "websocket", Authorization: "Bearer not-a-valid-device-token-000000000" },
      origin: null,
    });
    expect(response.status).toBe(401);
  });
});

describe("commands", () => {
  async function setup() {
    const cookie = await login("Regista");
    const control = await openControl(cookie);
    await control.nextType("snapshot");
    const { cameraId, deviceToken } = await pairCamera(cookie, "CAM CMD", nextSlot());
    const device = await openDevice(deviceToken);
    await device.nextType("welcome");
    device.send(hello);
    await control.next((m) => m.type === "camera_update" && (m.camera as { capabilities: unknown }).capabilities !== null);
    return { cookie, control, device, cameraId };
  }

  it("delivers a command to the phone and relays the real ACK to the control room", async () => {
    const { control, device, cameraId } = await setup();
    const commandId = uuid();
    control.send({ v: 1, type: "command", commandId, cameraId, command: "set_zoom", value: 2.5, issuedAt: Date.now() });

    const command = await device.nextType("command");
    expect(command).toMatchObject({ commandId, command: "set_zoom", value: 2.5, issuedBy: "Regista" });
    expect(command.seq).toBeGreaterThan(0);
    expect((command.expiresAt as number) - (command.sentAt as number)).toBe(15_000);

    const sent = await control.next((m) => m.type === "command_status" && m.commandId === commandId);
    expect(sent.status).toBe("sent");

    device.send({ v: 1, type: "ack", commandId, stage: "received", ok: true, ts: Date.now() });
    const received = await control.next((m) => m.type === "command_status" && m.commandId === commandId);
    expect(received.status).toBe("received");

    device.send({ v: 1, type: "ack", commandId, stage: "completed", ok: true, result: { zoom: 2.5 }, ts: Date.now() });
    const completed = await control.next((m) => m.type === "command_status" && m.commandId === commandId);
    expect(completed).toMatchObject({ status: "completed", result: { zoom: 2.5 } });
    device.close();
    control.close();
  });

  it("rejects replayed command ids", async () => {
    const { control, device, cameraId } = await setup();
    const message = { v: 1, type: "command", commandId: uuid(), cameraId, command: "pause", issuedAt: Date.now() };
    control.send(message);
    await device.nextType("command");
    control.send(message);
    const replay = await control.next((m) => m.type === "command_status" && m.status === "rejected");
    expect((replay.error as { code: string }).code).toBe("duplicate_command");
    device.close();
    control.close();
  });

  it("rejects commands for hardware the phone does not have", async () => {
    const { control, device, cameraId } = await setup();
    device.send({ v: 1, type: "state", state: { ...hello.state, facing: "front" } });
    await control.next((m) => m.type === "camera_update" && (m.camera as { state: { facing: string } }).state?.facing === "front");
    const commandId = uuid();
    control.send({ v: 1, type: "command", commandId, cameraId, command: "set_torch", value: true, issuedAt: Date.now() });
    const status = await control.next((m) => m.type === "command_status" && m.commandId === commandId);
    expect(status.status).toBe("rejected");
    expect((status.error as { code: string }).code).toBe("unsupported");
    expect(device.messages.find((m) => m.type === "command")).toBeUndefined();
    device.close();
    control.close();
  });

  it("fails immediately when the phone is offline (no fake ACK)", async () => {
    const cookie = await login();
    const control = await openControl(cookie);
    await control.nextType("snapshot");
    const { cameraId } = await pairCamera(cookie, "CAM OFF", nextSlot());
    const commandId = uuid();
    control.send({ v: 1, type: "command", commandId, cameraId, command: "start_stream", issuedAt: Date.now() });
    const status = await control.next((m) => m.type === "command_status" && m.commandId === commandId);
    expect(status.status).toBe("failed");
    expect((status.error as { code: string }).code).toBe("camera_offline");
    control.close();
  });

  it("times out commands that the phone never acknowledges", async () => {
    const { control, device, cameraId } = await setup();
    const commandId = uuid();
    control.send({ v: 1, type: "command", commandId, cameraId, command: "set_torch", value: true, issuedAt: Date.now() });
    await device.nextType("command");
    const stub = env.STUDIO.getByName("studio");
    await runInDurableObject(stub, (_instance, state) => {
      state.storage.sql.exec("UPDATE commands SET deadline = ? WHERE command_id = ?", Date.now() - 1, commandId);
    });
    await runDurableObjectAlarm(stub);
    const status = await control.next((m) => m.type === "command_status" && m.commandId === commandId && m.status === "timeout");
    expect((status.error as { code: string }).code).toBe("ack_timeout");
    device.close();
    control.close();
  });

  it("relays sanitized telemetry", async () => {
    const { control, device, cameraId } = await setup();
    device.send({ ...telemetryFixture, telemetry: { ...telemetryFixture.telemetry, injected: "<img onerror=alert(1)>" } });
    const message = await control.next((m) => m.type === "telemetry" && m.cameraId === cameraId);
    const telemetry = message.telemetry as Record<string, unknown>;
    expect(telemetry.bitrateKbps).toBe(4870);
    expect(telemetry.injected).toBeUndefined();
    device.close();
    control.close();
  });

  it("answers application pings with the server time", async () => {
    const { control, device } = await setup();
    device.send({ v: 1, type: "ping", t: 123 });
    const pong = await device.nextType("pong");
    expect(pong.t).toBe(123);
    expect(typeof pong.serverTime).toBe("number");
    device.close();
    control.close();
  });
});

describe("Cloudflare integration", () => {
  it("sends the SRT ingest configuration only to the phone", async () => {
    const cookie = await login();
    const { deviceToken, cameraId } = await pairCamera(cookie, "CAM CFG", nextSlot());
    const device = await openDevice(deviceToken);
    await device.nextType("welcome");
    device.send({ v: 1, type: "config_request" });
    const message = await device.nextType("config");
    const config = message.config as Record<string, unknown>;
    expect(message.error).toBeNull();
    expect(config).toMatchObject({ cameraId, protocol: "srt", host: "live.cf-test.invalid", port: 778 });
    const input = [...fake.inputs.values()].find((i) => i.meta.cameraId === cameraId);
    expect(config.passphrase).toBe(input?.srt.passphrase);
    expect((config.fallback as Record<string, unknown>).protocol).toBe("rtmps");
    expect(JSON.stringify(config)).not.toContain(input?.srtPlayback.passphrase ?? "none");

    // The control room camera list never contains ingest credentials.
    const list = await (await api("/api/cameras", { cookie })).text();
    expect(list).not.toContain(input?.srt.passphrase ?? "none");
    expect(list).not.toContain(input?.rtmps.streamKey ?? "none");
    device.close();
  });

  it("returns the OBS SRT playback URL on explicit request", async () => {
    const cookie = await login();
    const { cameraId } = await pairCamera(cookie, "CAM OBS", nextSlot());
    const response = await api(`/api/cameras/${cameraId}/playback`, { cookie });
    expect(response.status).toBe(200);
    const body = (await response.json()) as { srt: { obsUrl: string }; player: { iframeUrl: string } };
    const input = [...fake.inputs.values()].find((i) => i.meta.cameraId === cameraId);
    expect(body.srt.obsUrl).toBe(
      `srt://live.cf-test.invalid:778?passphrase=${input?.srtPlayback.passphrase}&streamid=${input?.srtPlayback.streamId}`,
    );
    expect(body.player.iframeUrl).toContain("https://customer-testcustomer123.cloudflarestream.com/");
  });

  it("verifies the webhook secret and updates the ingest state", async () => {
    const cookie = await login();
    const control = await openControl(cookie);
    await control.nextType("snapshot");
    const { cameraId } = await pairCamera(cookie, "CAM HOOK", nextSlot());
    const input = [...fake.inputs.values()].find((i) => i.meta.cameraId === cameraId);
    const payload = {
      name: "Live",
      data: { notification_name: "Stream Live Input", input_id: input?.uid, event_type: "live_input.connected", updated_at: new Date().toISOString() },
      ts: Math.floor(Date.now() / 1000),
    };
    const forged = await api("/api/webhooks/stream", { body: payload, origin: null, headers: { "cf-webhook-auth": "wrong" } });
    expect(forged.status).toBe(401);
    const ok = await api("/api/webhooks/stream", { body: payload, origin: null, headers: { "cf-webhook-auth": "test-webhook-secret" } });
    expect(ok.status).toBe(200);
    const update = await control.next(
      (m) => m.type === "camera_update" && (m.camera as { cloudflare: { state: string } }).cloudflare.state === "live",
    );
    expect((update.camera as { id: string }).id).toBe(cameraId);
    control.close();
  });

  it("revokes a device: socket closed, keys rotated, token refused", async () => {
    const cookie = await login();
    const { cameraId, deviceToken } = await pairCamera(cookie, "CAM REV", nextSlot());
    const device = await openDevice(deviceToken);
    await device.nextType("welcome");
    const input = [...fake.inputs.values()].find((i) => i.meta.cameraId === cameraId);
    const oldPassphrase = input?.srt.passphrase;
    const response = await api(`/api/cameras/${cameraId}`, { method: "DELETE", cookie });
    expect(((await response.json()) as { cloudflareAction: string }).cloudflareAction).toBe("keys_rotated");
    await device.nextType("revoked");
    const closed = await device.waitClosed();
    expect(closed.code).toBe(4001);
    expect(input?.srt.passphrase).not.toBe(oldPassphrase);
    const retry = await api("/ws/device", { headers: { Upgrade: "websocket", Authorization: `Bearer ${deviceToken}` }, origin: null });
    expect(retry.status).toBe(401);
  });

  it("keeps working when Cloudflare is down (camera is paired with a warning)", async () => {
    const cookie = await login();
    fake.failNext = 500;
    const start = (await (await api("/api/pair/start", { body: { deviceName: "Phone" }, origin: null })).json()) as { code: string };
    const response = await api("/api/cameras/claim", { body: { code: start.code, name: "CAM CF DOWN", slot: nextSlot() }, cookie });
    expect(response.status).toBe(201);
    const body = (await response.json()) as { warning: string; camera: { cloudflare: { liveInputId: string | null } } };
    expect(body.warning).toContain("Live input Cloudflare non creato");
    expect(body.camera.cloudflare.liveInputId).toBeNull();
  });
});

describe("static routing", () => {
  it("does not expose API routes on other methods", async () => {
    const response = await api("/api/cameras/claim", { method: "GET", cookie: await login() });
    expect(response.status).toBe(404);
  });

  it("uses the configured origin for cookies", () => {
    expect(ORIGIN.startsWith("https://")).toBe(true);
  });
});
