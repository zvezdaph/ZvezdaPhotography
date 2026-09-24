import { describe, expect, it } from "vitest";
import {
  StreamApi,
  StreamApiError,
  buildRtmpsUrl,
  buildSrtUrl,
  extractCustomerCode,
  parseEndpointUrl,
  playbackUrls,
} from "../src/cloudflare/stream";
import { mapLiveInputStatus, parseLiveWebhook, rawLiveInputStatus } from "../src/cloudflare/liveStatus";
import { buildStreamingConfig, checkCommandSupported, isErrorInfo } from "../src/logic";
import { sanitizeCapabilities, sanitizeState } from "../src/shared/protocol";
import hello from "../../../docs/protocol-fixtures/hello.json";

type Call = { url: string; method: string; headers: Headers; body: string | null };

function fakeFetch(responder: (call: Call) => Response): { fetcher: typeof fetch; calls: Call[] } {
  const calls: Call[] = [];
  const fetcher = (async (input: RequestInfo | URL, init?: RequestInit) => {
    const request = new Request(input as RequestInfo, init);
    const call = {
      url: request.url,
      method: request.method,
      headers: request.headers,
      body: init?.body ? String(init.body) : null,
    };
    calls.push(call);
    return responder(call);
  }) as typeof fetch;
  return { fetcher, calls };
}

const liveInput = {
  uid: "0123456789abcdef0123456789abcdef",
  enabled: true,
  srt: { url: "srt://live.cf-test.invalid:778", streamId: "0123456789abcdef0123456789abcdef", passphrase: "p4ssphr4se-for-tests" },
  rtmps: { url: "rtmps://live.cf-test.invalid:443/live/", streamKey: "key-for-tests" },
  srtPlayback: { url: "srt://live.cf-test.invalid:778", streamId: "play0123", passphrase: "playback-pass" },
  rtmpsPlayback: { url: "rtmps://live.cf-test.invalid:443/live/", streamKey: "playback-key" },
  status: null,
};

describe("StreamApi", () => {
  it("creates a live input with the documented body and bearer token", async () => {
    const { fetcher, calls } = fakeFetch(() => Response.json({ success: true, errors: [], result: liveInput }));
    const api = new StreamApi("acc123", "secret-token", fetcher);
    const result = await api.createLiveInput({
      name: "CAM 01 - SALA",
      cameraId: "cam_1",
      recordingMode: "automatic",
      deleteRecordingAfterDays: 30,
      preferLowLatency: false,
    });
    expect(result.uid).toBe(liveInput.uid);
    expect(calls[0].url).toBe("https://api.cloudflare.com/client/v4/accounts/acc123/stream/live_inputs");
    expect(calls[0].method).toBe("POST");
    expect(calls[0].headers.get("Authorization")).toBe("Bearer secret-token");
    const body = JSON.parse(calls[0].body ?? "{}");
    expect(body.recording.mode).toBe("automatic");
    expect(body.meta.name).toBe("CAM 01 - SALA");
    expect(body.deleteRecordingAfterDays).toBe(30);
    expect(body.enabled).toBe(true);
    expect(body.preferLowLatency).toBeUndefined();
  });

  it("uses PUT for enable/disable and POST for key rotation", async () => {
    const { fetcher, calls } = fakeFetch(() => Response.json({ success: true, errors: [], result: liveInput }));
    const api = new StreamApi("acc", "tok", fetcher);
    await api.setEnabled(liveInput.uid, false);
    await api.rotateKeys(liveInput.uid);
    expect(calls[0].method).toBe("PUT");
    expect(JSON.parse(calls[0].body ?? "{}")).toEqual({ enabled: false });
    expect(calls[1].method).toBe("POST");
    expect(calls[1].url.endsWith(`/live_inputs/${liveInput.uid}/rotate_keys`)).toBe(true);
  });

  it("raises a StreamApiError without leaking the token", async () => {
    const { fetcher } = fakeFetch(() =>
      Response.json({ success: false, errors: [{ code: 10000, message: "Authentication error" }] }, { status: 403 }),
    );
    const api = new StreamApi("acc", "super-secret-token", fetcher);
    const error = await api.getLiveInput(liveInput.uid).catch((e: unknown) => e);
    expect(error).toBeInstanceOf(StreamApiError);
    expect((error as Error).message).toContain("403");
    expect((error as Error).message).not.toContain("super-secret-token");
    expect((error as Error).message).not.toContain(liveInput.uid);
  });

  it("reports network failures", async () => {
    const api = new StreamApi("acc", "tok", (async () => {
      throw new TypeError("network down");
    }) as typeof fetch);
    await expect(api.getLiveInput(liveInput.uid)).rejects.toThrow(/unreachable/);
  });
});

describe("URL helpers", () => {
  it("parses endpoints returned by the API", () => {
    expect(parseEndpointUrl("srt://live.cf-test.invalid:778")).toEqual({ url: "srt://live.cf-test.invalid:778", host: "live.cf-test.invalid", port: 778 });
    expect(parseEndpointUrl("rtmps://live.cf-test.invalid:443/live/")?.port).toBe(443);
    expect(parseEndpointUrl("rtmps://live.cf-test.invalid/live/")?.port).toBe(443);
    expect(parseEndpointUrl("srt://no-port.invalid")).toBeNull();
    expect(parseEndpointUrl("not a url")).toBeNull();
  });

  it("builds the OBS SRT and RTMPS URLs", () => {
    expect(buildSrtUrl("srt://live.cf-test.invalid:778", "play0123", "pass word")).toBe(
      "srt://live.cf-test.invalid:778?passphrase=pass%20word&streamid=play0123",
    );
    expect(buildSrtUrl(undefined, "x", "y")).toBeNull();
    expect(buildRtmpsUrl("rtmps://live.cf-test.invalid:443/live/", "abc")).toBe("rtmps://live.cf-test.invalid:443/live/abc");
    expect(buildRtmpsUrl("rtmps://live.cf-test.invalid:443/live", "abc")).toBe("rtmps://live.cf-test.invalid:443/live/abc");
  });

  it("derives player URLs from the customer code", () => {
    expect(extractCustomerCode(undefined, "https://customer-abc123.cloudflarestream.com/uid/watch")).toBe("abc123");
    expect(playbackUrls("abc123", liveInput.uid)?.hlsUrl).toBe(
      `https://customer-abc123.cloudflarestream.com/${liveInput.uid}/manifest/video.m3u8`,
    );
    expect(playbackUrls("bad code!", liveInput.uid)).toBeNull();
    expect(playbackUrls(null, liveInput.uid)).toBeNull();
  });
});

describe("live input status", () => {
  it("maps documented states", () => {
    expect(mapLiveInputStatus("connected")).toBe("live");
    expect(mapLiveInputStatus("reconnected")).toBe("live");
    expect(mapLiveInputStatus("reconnecting")).toBe("reconnecting");
    expect(mapLiveInputStatus("client_disconnect")).toBe("offline");
    expect(mapLiveInputStatus("ttl_exceeded")).toBe("offline");
    expect(mapLiveInputStatus("failed_to_connect")).toBe("error");
    expect(mapLiveInputStatus(null)).toBe("offline");
    expect(mapLiveInputStatus("something_new")).toBe("unknown");
  });

  it("accepts string and object status shapes", () => {
    expect(rawLiveInputStatus("connected")).toBe("connected");
    expect(rawLiveInputStatus({ current: { reason: "connected", state: "connected" } })).toBe("connected");
    expect(rawLiveInputStatus({ current: { state: "disconnected" } })).toBe("disconnected");
    expect(rawLiveInputStatus(null)).toBeNull();
  });

  it("parses the documented webhook payloads", () => {
    const disconnected = parseLiveWebhook({
      name: "Live Webhook Test",
      text: "Notification type: Stream Live Input",
      data: {
        notification_name: "Stream Live Input",
        input_id: "eb222fcca08eeb1ae84c981ebe8aeeb6",
        event_type: "live_input.disconnected",
        updated_at: "2022-01-13T11:43:41.855717910Z",
      },
      ts: 1642074233,
    });
    expect(disconnected?.state).toBe("offline");
    const errored = parseLiveWebhook({
      data: {
        input_id: "eb222fcca08eeb1ae84c981ebe8aeeb6",
        event_type: "live_input.errored",
        updated_at: "2024-07-09T18:07:51.077371662Z",
        live_input_errored: { error: { code: "ERR_GOP_OUT_OF_RANGE", message: "Input GOP size or keyframe interval is out of range." } },
      },
    });
    expect(errored?.state).toBe("error");
    expect(errored?.errorCode).toBe("ERR_GOP_OUT_OF_RANGE");
    expect(parseLiveWebhook({ data: { input_id: "x", event_type: "video.ready" } })).toBeNull();
  });
});

describe("streaming config", () => {
  const defaults = { resolution: "1080p" as const, fps: 30, videoBitrateKbps: 5000, audioBitrateKbps: 128, srtLatencyMs: 500 };

  it("uses SRT as primary and RTMPS as fallback", () => {
    const config = buildStreamingConfig({ id: "cam_1", name: "CAM 01" }, liveInput, defaults, 1);
    expect(isErrorInfo(config)).toBe(false);
    if (isErrorInfo(config)) return;
    expect(config.protocol).toBe("srt");
    expect(config.host).toBe("live.cf-test.invalid");
    expect(config.port).toBe(778);
    expect(config.streamId).toBe(liveInput.srt.streamId);
    expect(config.passphrase).toBe(liveInput.srt.passphrase);
    expect(config.fallback?.protocol).toBe("rtmps");
    expect(config.fallback?.streamKey).toBe("key-for-tests");
    // playback credentials are never part of the phone configuration
    expect(JSON.stringify(config)).not.toContain("playback-pass");
    expect(JSON.stringify(config)).not.toContain("playback-key");
  });

  it("falls back to RTMPS when SRT is missing", () => {
    const config = buildStreamingConfig({ id: "cam_1", name: "CAM 01" }, { ...liveInput, srt: undefined }, defaults, 1);
    expect(!isErrorInfo(config) && config.protocol).toBe("rtmps");
  });

  it("refuses disabled inputs", () => {
    const config = buildStreamingConfig({ id: "cam_1", name: "CAM 01" }, { ...liveInput, enabled: false }, defaults, 1);
    expect(isErrorInfo(config) && config.code).toBe("live_input_disabled");
  });
});

describe("server side capability check", () => {
  const caps = sanitizeCapabilities(hello.capabilities);
  const state = sanitizeState(hello.state);

  it("rejects hardware features the phone does not have", () => {
    const front = state ? { ...state, facing: "front" as const } : null;
    expect(checkCommandSupported(caps, front, "set_torch", true)?.code).toBe("unsupported");
    expect(checkCommandSupported(caps, front, "set_torch", false)).toBeNull();
    expect(checkCommandSupported(caps, front, "focus_point", { x: 0.5, y: 0.5 })?.code).toBe("unsupported");
    expect(checkCommandSupported(caps, state, "focus_point", { x: 0.5, y: 0.5 })).toBeNull();
    expect(checkCommandSupported(caps, front, "set_fps", 60)?.code).toBe("unsupported");
    expect(checkCommandSupported(caps, state, "set_fps", 60)).toBeNull();
  });

  it("lets commands through when capabilities are unknown", () => {
    expect(checkCommandSupported(null, null, "set_torch", true)).toBeNull();
  });
});
