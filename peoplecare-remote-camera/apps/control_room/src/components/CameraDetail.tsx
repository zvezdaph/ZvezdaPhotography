import { useEffect, useRef, useState } from "preact/hooks";
import type { CommandName } from "@protocol";
import { MAX_BITRATE_KBPS, MIN_BITRATE_KBPS } from "@protocol";
import { api, ApiError } from "../api";
import { useAppState, useServices, useTick } from "../context";
import { connectionQuality, controlAvailability, tallyLabel, tallyState } from "../controls";
import type { ControlAvailability } from "../controls";
import {
  cameraTitle,
  cloudflareLabel,
  commandLabel,
  formatAgo,
  formatBytes,
  formatDuration,
  formatKbps,
  formatTime,
  networkLabel,
  slotLabel,
} from "../format";
import { latestCommandFor } from "../store";
import type { CameraView, CommandView, EventView, PlaybackInfo } from "../types";
import { batteryText } from "./CameraTile";
import { CommandButton, Dot, Metric, Modal, Pill, Section } from "./common";
import { EventLog } from "./EventLog";

const PRESETS = [
  { id: "low", label: "LOW", detail: "720p · 25 fps · 2 Mbps" },
  { id: "standard", label: "STANDARD", detail: "1080p · 25/30 fps · 5 Mbps" },
  { id: "high", label: "HIGH", detail: "1080p · 30 fps · 7 Mbps" },
] as const;

export function CameraDetail(props: { cameraId: string }) {
  const { navigate } = useServices();
  const camera = useAppState((s) => s.cameras[props.cameraId] ?? null);
  const events = useAppState((s) => s.events.filter((e) => e.cameraId === props.cameraId));
  const commands = useAppState((s) =>
    Object.values(s.commands)
      .filter((c) => c.cameraId === props.cameraId)
      .sort((a, b) => b.updatedAt - a.updatedAt)
      .slice(0, 12),
  );
  if (!camera) {
    return (
      <main class="detail">
        <p class="notice">Camera non trovata (forse è stata rimossa).</p>
        <button type="button" class="btn btn-primary" onClick={() => navigate("#/")}>
          Torna alla dashboard
        </button>
      </main>
    );
  }
  return <CameraDetailView camera={camera} events={events} commands={commands} />;
}

function CameraDetailView(props: { camera: CameraView; events: EventView[]; commands: CommandView[] }) {
  const { camera } = props;
  const { navigate } = useServices();
  const tally = tallyState(camera);
  const controls = controlAvailability(camera);
  const [renaming, setRenaming] = useState(false);
  const [confirmRevoke, setConfirmRevoke] = useState(false);

  return (
    <main class="detail">
      <div class="detail-head">
        <button type="button" class="btn btn-ghost" onClick={() => navigate("#/")}>
          ← Dashboard
        </button>
        <div class="detail-title">
          {cameraTitle(camera.slot, camera.name) === camera.name ? null : <span class="tile-slot">{slotLabel(camera.slot)}</span>}
          <h1>{camera.name}</h1>
          <Pill tone={tally === "live" ? "red" : tally === "offline" || tally === "ready" ? (camera.online ? "green" : "gray") : tally === "error" ? "red" : "amber"} pulse={tally === "live"}>
            {tally === "live" ? "● " : ""}
            {tallyLabel(tally)}
          </Pill>
          <Pill tone={camera.online ? "green" : "gray"}>{camera.online ? "ONLINE" : "OFFLINE"}</Pill>
        </div>
        <div class="detail-actions">
          <button type="button" class="btn btn-ghost" onClick={() => setRenaming(true)}>
            Rinomina
          </button>
          <button type="button" class="btn btn-danger-ghost" onClick={() => setConfirmRevoke(true)}>
            Revoca dispositivo
          </button>
        </div>
      </div>
      {!controls.online ? (
        <p class="notice notice-warning">
          {controls.reasons.all}. Ultimo contatto: {formatAgo(camera.lastSeenAt)}. I comandi sono disabilitati finché il telefono non si riconnette.
        </p>
      ) : null}
      <div class="detail-grid">
        <div class="detail-left">
          <Preview camera={camera} controls={controls} />
          <QualityPanel camera={camera} />
          <ObsPanel camera={camera} />
        </div>
        <div class="detail-right">
          <LiveControls camera={camera} controls={controls} />
          <CameraControls camera={camera} controls={controls} />
          <FormatControls camera={camera} controls={controls} />
          <RecordingControls camera={camera} controls={controls} />
          <CloudflarePanel camera={camera} />
          <CommandFeed commands={props.commands} />
        </div>
      </div>
      <EventLog events={props.events} title="Log camera" />
      {renaming ? <RenameDialog camera={camera} onClose={() => setRenaming(false)} /> : null}
      {confirmRevoke ? <RevokeDialog camera={camera} onClose={() => setConfirmRevoke(false)} /> : null}
    </main>
  );
}

function useCommand(camera: CameraView) {
  const { sender } = useServices();
  // Single subscription; `last(name)` is a plain lookup (safe to call conditionally).
  const state = useAppState((s) => s);
  return {
    send: (command: CommandName, value?: unknown) => sender.send(camera.id, command, value),
    throttled: (command: CommandName, value: unknown) => sender.sendThrottled(camera.id, command, value),
    last: (command: CommandName) => latestCommandFor(state, camera.id, command),
  };
}

function Preview(props: { camera: CameraView; controls: ControlAvailability }) {
  const { camera, controls } = props;
  const { send } = useCommand(camera);
  const [focusMode, setFocusMode] = useState(false);
  const [marker, setMarker] = useState<{ x: number; y: number } | null>(null);
  const boxRef = useRef<HTMLDivElement>(null);
  const player = camera.playback?.iframeUrl;
  const portrait = camera.state?.orientation === "portrait";
  const live = camera.state?.streamStatus === "live";

  function onFocusClick(event: MouseEvent) {
    const box = boxRef.current;
    if (!box) return;
    const rect = box.getBoundingClientRect();
    // The player keeps the aspect ratio of the stream inside a 16:9 box.
    const aspect = portrait ? 9 / 16 : 16 / 9;
    let width = rect.width;
    let height = rect.width / aspect;
    if (height > rect.height) {
      height = rect.height;
      width = rect.height * aspect;
    }
    const left = rect.left + (rect.width - width) / 2;
    const top = rect.top + (rect.height - height) / 2;
    const x = (event.clientX - left) / width;
    const y = (event.clientY - top) / height;
    if (x < 0 || x > 1 || y < 0 || y > 1) return;
    setMarker({ x: event.clientX - rect.left, y: event.clientY - rect.top });
    setTimeout(() => setMarker(null), 1200);
    send("focus_point", { x: Math.round(x * 1000) / 1000, y: Math.round(y * 1000) / 1000 });
  }

  return (
    <Section
      title="Anteprima"
      actions={
        <button
          type="button"
          class={`btn btn-small ${focusMode ? "btn-active" : "btn-ghost"}`}
          disabled={!controls.focusPoint}
          title={controls.focusPoint ? "Clicca sull'anteprima per mettere a fuoco" : controls.reasons.focusPoint ?? controls.reasons.all}
          onClick={() => setFocusMode(!focusMode)}
        >
          ◎ Punto di fuoco
        </button>
      }
    >
      <div class="preview" ref={boxRef}>
        {player ? (
          <iframe
            key={player}
            src={player}
            title={`Anteprima ${camera.name}`}
            allow="accelerometer; gyroscope; autoplay; encrypted-media; picture-in-picture; fullscreen"
            referrerpolicy="no-referrer"
            loading="lazy"
          />
        ) : (
          <div class="preview-empty">
            {camera.cloudflare.state === "unconfigured"
              ? "Cloudflare Stream non configurato per questa camera"
              : "Anteprima disponibile quando Cloudflare ha il customer code (CLOUDFLARE_STREAM_CUSTOMER_CODE) o dopo la prima diretta"}
          </div>
        )}
        {focusMode ? <div class="focus-overlay" onClick={onFocusClick} title="Clicca per mettere a fuoco" /> : null}
        {marker ? <span class="focus-marker" style={{ left: `${marker.x}px`, top: `${marker.y}px` }} /> : null}
        {live ? <span class="preview-tally">● LIVE</span> : null}
      </div>
      <p class="hint">
        Anteprima via Cloudflare Stream Player (HLS/LL-HLS, alcuni secondi di ritardo). Il riferimento a latenza minima è OBS con SRT
        playback.
      </p>
    </Section>
  );
}

function LiveControls(props: { camera: CameraView; controls: ControlAvailability }) {
  const { camera, controls } = props;
  const { send, last } = useCommand(camera);
  const paused = camera.state?.paused ?? false;
  return (
    <Section title="Diretta">
      <div class="button-row">
        <CommandButton big variant="live" label="START" disabled={!controls.start} last={last("start_stream")} onClick={() => send("start_stream")} title={controls.reasons.all} />
        {paused ? (
          <CommandButton big variant="primary" label="RESUME" disabled={!controls.resume} last={last("resume")} onClick={() => send("resume")} />
        ) : (
          <CommandButton big variant="primary" label="PAUSE" disabled={!controls.pause} last={last("pause")} onClick={() => send("pause")} />
        )}
        <CommandButton big variant="danger" label="STOP" disabled={!controls.stop} last={last("stop_stream")} onClick={() => send("stop_stream")} />
      </div>
      <div class="button-row">
        <CommandButton label="RECONNECT" disabled={!controls.reconnect} last={last("reconnect")} onClick={() => send("reconnect")} title="Riconnette SRT senza fermare encoder e camera" />
        <CommandButton label="RESTART STREAM" disabled={!controls.restart} last={last("restart_stream")} onClick={() => send("restart_stream")} title="Ferma e riavvia la trasmissione" />
      </div>
      <div class="button-row">
        <CommandButton
          variant={camera.state?.audioEnabled === false ? "active" : "ghost"}
          label={camera.state?.audioEnabled === false ? "🔇 MIC OFF" : "🎙 MIC ON"}
          disabled={!controls.mic}
          last={last("set_audio_enabled")}
          onClick={() => send("set_audio_enabled", camera.state?.audioEnabled === false)}
        />
        <CommandButton
          variant={camera.state?.videoEnabled === false ? "active" : "ghost"}
          label={camera.state?.videoEnabled === false ? "VIDEO OFF" : "VIDEO ON"}
          disabled={!controls.video}
          last={last("set_video_enabled")}
          onClick={() => send("set_video_enabled", camera.state?.videoEnabled === false)}
        />
      </div>
    </Section>
  );
}

function CameraControls(props: { camera: CameraView; controls: ControlAvailability }) {
  const { camera, controls } = props;
  const { send, throttled, last } = useCommand(camera);
  const [zoom, setZoom] = useState(controls.zoom.value);
  const [exposure, setExposure] = useState(controls.exposure.value);
  const dragging = useRef(false);
  useEffect(() => {
    if (!dragging.current) setZoom(controls.zoom.value);
  }, [controls.zoom.value]);
  useEffect(() => {
    if (!dragging.current) setExposure(controls.exposure.value);
  }, [controls.exposure.value]);
  const facing = camera.state?.facing ?? "back";
  const evStep = controls.exposure.step || 0;
  return (
    <Section title="Camera">
      <div class="button-row">
        <CommandButton variant={facing === "front" ? "active" : "ghost"} label="FRONT CAMERA" disabled={!controls.front} last={last("switch_camera")} onClick={() => send("switch_camera", "front")} />
        <CommandButton variant={facing === "back" ? "active" : "ghost"} label="REAR CAMERA" disabled={!controls.back} last={last("switch_camera")} onClick={() => send("switch_camera", "back")} />
      </div>
      <div class="slider-row" title={controls.reasons.zoom}>
        <span class="slider-label">Zoom</span>
        <button type="button" class="btn btn-small btn-ghost" disabled={!controls.zoom.enabled} onClick={() => send("zoom_out")}>
          −
        </button>
        <input
          type="range"
          min={controls.zoom.min}
          max={controls.zoom.max}
          step={0.1}
          value={zoom}
          disabled={!controls.zoom.enabled}
          onPointerDown={() => (dragging.current = true)}
          onPointerUp={() => (dragging.current = false)}
          onInput={(e) => {
            const value = Number((e.target as HTMLInputElement).value);
            setZoom(value);
            throttled("set_zoom", value);
          }}
        />
        <button type="button" class="btn btn-small btn-ghost" disabled={!controls.zoom.enabled} onClick={() => send("zoom_in")}>
          +
        </button>
        <span class="slider-value">{zoom.toFixed(1)}×</span>
      </div>
      <div class="button-row">
        <CommandButton
          variant={camera.state?.autofocus ? "active" : "ghost"}
          label="AUTO FOCUS"
          disabled={!controls.autofocus}
          title={controls.autofocus ? "Autofocus continuo" : "Autofocus non supportato"}
          last={last("set_autofocus")}
          onClick={() => send("set_autofocus", true)}
        />
        <CommandButton
          variant={camera.state?.torch ? "active" : "ghost"}
          label={camera.state?.torch ? "TORCH ON" : "TORCH OFF"}
          disabled={!controls.torch}
          title={controls.reasons.torch}
          last={last("set_torch")}
          onClick={() => send("set_torch", !camera.state?.torch)}
        />
      </div>
      <div class="slider-row" title={controls.reasons.exposure}>
        <span class="slider-label">Esposizione</span>
        <input
          type="range"
          min={controls.exposure.min}
          max={controls.exposure.max}
          step={1}
          value={exposure}
          disabled={!controls.exposure.enabled}
          onPointerDown={() => (dragging.current = true)}
          onPointerUp={() => (dragging.current = false)}
          onInput={(e) => {
            const value = Math.round(Number((e.target as HTMLInputElement).value));
            setExposure(value);
            throttled("set_exposure", value);
          }}
        />
        <span class="slider-value">{evStep ? `${exposure * evStep >= 0 ? "+" : ""}${(exposure * evStep).toFixed(1)} EV` : exposure}</span>
        <button type="button" class="btn btn-small btn-ghost" disabled={!controls.exposure.enabled} onClick={() => send("set_exposure", 0)}>
          0
        </button>
      </div>
    </Section>
  );
}

function FormatControls(props: { camera: CameraView; controls: ControlAvailability }) {
  const { camera, controls } = props;
  const { send, last } = useCommand(camera);
  const state = camera.state;
  const [manualKbps, setManualKbps] = useState(state?.targetBitrateKbps || 5000);
  useEffect(() => {
    if (state?.targetBitrateKbps) setManualKbps(state.targetBitrateKbps);
  }, [state?.targetBitrateKbps]);
  const streaming = state?.streamStatus === "live" || state?.streamStatus === "reconnecting";
  return (
    <Section title="Formato">
      {streaming ? <p class="hint">Cambiare risoluzione o FPS durante la diretta riavvia l'encoder (breve interruzione).</p> : null}
      <div class="control-grid">
        <span class="slider-label">Risoluzione</span>
        <div class="segmented">
          {controls.resolutions.map((r) => (
            <button
              type="button"
              key={r.value}
              class={state?.resolution === r.value ? "active" : ""}
              disabled={!r.enabled || state?.resolution === r.value}
              onClick={() => send("set_resolution", r.value)}
            >
              {r.value.toUpperCase()}
            </button>
          ))}
        </div>
        <span class="slider-label">FPS</span>
        <div class="segmented">
          {controls.fps.map((f) => (
            <button
              type="button"
              key={f.value}
              class={state?.fps === f.value ? "active" : ""}
              disabled={!f.enabled || state?.fps === f.value}
              title={f.enabled ? undefined : "Non supportato dall'hardware a questa risoluzione"}
              onClick={() => send("set_fps", f.value)}
            >
              {f.value}
            </button>
          ))}
        </div>
        <span class="slider-label">Bitrate</span>
        <div class="segmented">
          <button type="button" class={state?.bitrateMode === "auto" ? "active" : ""} disabled={!controls.bitrate || state?.bitrateMode === "auto"} onClick={() => send("set_bitrate", { mode: "auto" })}>
            AUTO
          </button>
          <button type="button" class={state?.bitrateMode === "manual" ? "active" : ""} disabled={!controls.bitrate} onClick={() => send("set_bitrate", { mode: "manual", kbps: manualKbps })}>
            MANUALE
          </button>
        </div>
      </div>
      <div class="slider-row">
        <span class="slider-label">Video</span>
        <input
          type="range"
          min={MIN_BITRATE_KBPS}
          max={Math.min(MAX_BITRATE_KBPS, camera.capabilities?.maxBitrateKbps ?? MAX_BITRATE_KBPS)}
          step={250}
          value={manualKbps}
          disabled={!controls.bitrate}
          onInput={(e) => setManualKbps(Number((e.target as HTMLInputElement).value))}
        />
        <span class="slider-value">{formatKbps(manualKbps)}</span>
        <CommandButton label="Applica" disabled={!controls.bitrate} last={last("set_bitrate")} onClick={() => send("set_bitrate", { mode: "manual", kbps: manualKbps })} />
      </div>
      <div class="preset-row">
        {PRESETS.map((p) => (
          <CommandButton key={p.id} label={p.label} title={p.detail} disabled={!controls.bitrate} last={last("set_preset")} onClick={() => send("set_preset", p.id)} />
        ))}
      </div>
      <p class="hint">
        Target attuale: {state ? `${state.resolution} · ${state.fps} fps · ${formatKbps(state.targetBitrateKbps)} (${state.bitrateMode === "auto" ? "AUTO" : "MANUALE"})` : "—"} ·
        Protocollo: {state?.protocol?.toUpperCase() ?? "—"}
      </p>
    </Section>
  );
}

function RecordingControls(props: { camera: CameraView; controls: ControlAvailability }) {
  const { camera, controls } = props;
  const { send, last } = useCommand(camera);
  const recording = camera.state?.recording ?? false;
  const free = camera.telemetry?.recording?.freeBytes;
  return (
    <Section title="Registrazione backup (MP4 sul telefono)">
      <div class="button-row">
        <CommandButton
          variant={recording ? "live" : "ghost"}
          label={recording ? "● RECORD BACKUP ON" : "RECORD BACKUP OFF"}
          disabled={!controls.record}
          title={controls.reasons.record}
          last={last("set_record")}
          onClick={() => send("set_record", !recording)}
        />
        <span class="hint">Spazio libero: {formatBytes(free)}</span>
      </div>
    </Section>
  );
}

function QualityPanel(props: { camera: CameraView }) {
  const { camera } = props;
  const t = camera.telemetry;
  const quality = connectionQuality(camera);
  useTick(1000);
  const qualityTone = quality === "good" ? "green" : quality === "fair" ? "amber" : quality === "poor" ? "red" : "gray";
  const qualityLabel = quality === "good" ? "Ottima" : quality === "fair" ? "Discreta" : quality === "poor" ? "Scarsa" : "—";
  return (
    <Section title="Connessione e telemetria">
      <div class="metrics">
        <Metric label="Qualità" value={qualityLabel} tone={qualityTone} />
        <Metric label="Bitrate effettivo" value={t ? formatKbps(t.bitrateKbps) : "—"} />
        <Metric label="Upload" value={t?.uploadKbps ? formatKbps(t.uploadKbps) : "—"} />
        <Metric label="Banda uplink stimata" value={t?.network.uplinkKbps ? formatKbps(t.network.uplinkKbps) : "n.d."} />
        <Metric label="Coda invio" value={t?.queuePercent !== null && t?.queuePercent !== undefined ? `${t.queuePercent.toFixed(0)}%` : "—"} />
        <Metric label="FPS" value={t ? Math.round(t.fps) : "—"} />
        <Metric label="Risoluzione" value={t?.resolution || "—"} />
        <Metric label="Rete" value={`${networkLabel(t?.network.type)}${t?.network.metered ? " (a consumo)" : ""}`} />
        <Metric label="Batteria" value={batteryText(camera)} tone={(camera.telemetry?.battery.percent ?? 100) < 20 ? "red" : undefined} />
        <Metric
          label="Temperatura"
          value={t?.battery.temperatureC !== null && t?.battery.temperatureC !== undefined ? `${t.battery.temperatureC.toFixed(1)} °C` : "n.d."}
          tone={(t?.battery.temperatureC ?? 0) > 42 ? "red" : undefined}
        />
        <Metric label="Stato termico" value={t?.thermal ?? "n.d."} tone={t?.thermal && !["none", "light"].includes(t.thermal) ? "amber" : undefined} />
        <Metric label="Uptime stream" value={formatDuration(t?.uptimeSec)} />
        <Metric label="Riconnessioni" value={t?.reconnects ?? 0} tone={(t?.reconnects ?? 0) > 0 ? "amber" : undefined} />
        <Metric label="Zoom" value={t ? `${t.zoom.toFixed(1)}×` : "—"} />
        <Metric label="Torcia" value={t?.torch ? "ON" : "OFF"} />
        <Metric label="Telefono" value={camera.device.model ?? "—"} />
      </div>
      {t && t.recentErrors.length > 0 ? (
        <div class="recent-errors">
          <h4>Errori recenti</h4>
          <ul>
            {t.recentErrors.map((e, i) => (
              <li key={i}>
                <time>{formatTime(e.ts)}</time> <code>{e.code}</code> {e.message}
              </li>
            ))}
          </ul>
        </div>
      ) : null}
      <p class="hint">Ultimo aggiornamento: {t ? formatAgo(t.ts) : "mai"} · App {camera.device.appVersion ?? "?"} · {camera.device.osVersion ?? ""}</p>
    </Section>
  );
}

function ObsPanel(props: { camera: CameraView }) {
  const { store } = useServices();
  const [info, setInfo] = useState<PlaybackInfo | null>(null);
  const [busy, setBusy] = useState(false);
  const [revealed, setRevealed] = useState(false);

  async function load() {
    setBusy(true);
    try {
      setInfo(await api.playback(props.camera.id));
      setRevealed(false);
    } catch (err) {
      store.toast("error", err instanceof ApiError ? err.message : "Impossibile leggere le credenziali di playback");
    } finally {
      setBusy(false);
    }
  }

  async function copy(text: string | null | undefined) {
    if (!text) return;
    try {
      await navigator.clipboard.writeText(text);
      store.toast("success", "Copiato negli appunti");
    } catch {
      store.toast("error", "Copia non riuscita");
    }
  }

  const url = info?.srt?.obsUrl ?? null;
  return (
    <Section title="OBS · SRT playback">
      <p class="hint">
        In OBS: Fonti → + → Sorgente multimediale → togli «File locale» → Input = URL qui sotto. Guida completa in docs/OBS_SETUP.md.
      </p>
      {!info ? (
        <button type="button" class="btn btn-ghost" disabled={busy || !props.camera.cloudflare.liveInputId} onClick={() => void load()}>
          {busy ? "Carico…" : "Mostra URL SRT per OBS"}
        </button>
      ) : (
        <div class="secret-box">
          {url ? (
            <>
              <code class="secret">{revealed ? url : url.replace(/(passphrase=)[^&]+/, "$1••••••••••")}</code>
              <div class="button-row">
                <button type="button" class="btn btn-small btn-ghost" onClick={() => setRevealed(!revealed)}>
                  {revealed ? "Nascondi" : "Mostra"}
                </button>
                <button type="button" class="btn btn-small btn-primary" onClick={() => void copy(url)}>
                  Copia URL OBS
                </button>
                <button type="button" class="btn btn-small btn-ghost" onClick={() => setInfo(null)}>
                  Chiudi
                </button>
              </div>
              <p class="hint">Questo URL permette di vedere la diretta: trattalo come una password.</p>
            </>
          ) : (
            <p class="notice notice-warning">Il live input non ha restituito credenziali di SRT playback.</p>
          )}
          {info.rtmps?.obsUrl ? (
            <details>
              <summary>Alternativa RTMPS playback</summary>
              <button type="button" class="btn btn-small btn-ghost" onClick={() => void copy(info.rtmps?.obsUrl)}>
                Copia URL RTMPS playback
              </button>
            </details>
          ) : null}
        </div>
      )}
    </Section>
  );
}

function CloudflarePanel(props: { camera: CameraView }) {
  const { store } = useServices();
  const { camera } = props;
  const [busy, setBusy] = useState<string | null>(null);
  const cf = camera.cloudflare;

  async function action(name: "create" | "enable" | "disable" | "rotate" | "refresh") {
    if (name === "rotate" && !confirm("Ruotare le chiavi del live input? Il telefono riceverà le nuove credenziali e si riconnetterà.")) return;
    setBusy(name);
    try {
      const result = await api.liveInput(camera.id, name);
      store.toast("success", result.message);
    } catch (err) {
      store.toast("error", err instanceof ApiError ? err.message : "Operazione non riuscita");
    } finally {
      setBusy(null);
    }
  }

  const tone = cf.state === "live" ? "green" : cf.state === "reconnecting" ? "amber" : cf.state === "error" || cf.state === "disabled" ? "red" : "gray";
  return (
    <Section title="Cloudflare Stream">
      <div class="cf-row">
        <Dot tone={tone} /> <strong>{cloudflareLabel(cf.state)}</strong>
        {cf.status ? <code>{cf.status}</code> : null}
        {cf.statusAt ? <span class="hint">({formatAgo(cf.statusAt)})</span> : null}
      </div>
      {cf.error ? <p class="notice notice-error">{cf.error}</p> : null}
      {cf.liveInputId ? <p class="hint">Live input: {cf.liveInputId.slice(0, 8)}…</p> : null}
      <div class="button-row">
        {!cf.liveInputId ? (
          <button type="button" class="btn btn-small btn-primary" disabled={!cf.configured || busy !== null} onClick={() => void action("create")}>
            Crea live input
          </button>
        ) : (
          <>
            <button type="button" class="btn btn-small btn-ghost" disabled={busy !== null} onClick={() => void action("refresh")}>
              Aggiorna stato
            </button>
            {cf.state === "disabled" ? (
              <button type="button" class="btn btn-small btn-ghost" disabled={busy !== null} onClick={() => void action("enable")}>
                Abilita input
              </button>
            ) : (
              <button type="button" class="btn btn-small btn-ghost" disabled={busy !== null} onClick={() => void action("disable")}>
                Disabilita input
              </button>
            )}
            <button type="button" class="btn btn-small btn-ghost" disabled={busy !== null} onClick={() => void action("rotate")}>
              Ruota chiavi
            </button>
          </>
        )}
      </div>
    </Section>
  );
}

function CommandFeed(props: { commands: CommandView[] }) {
  useTick(2000);
  return (
    <Section title="Comandi e ACK">
      <ul class="command-feed">
        {props.commands.length === 0 ? <li class="log-empty">Nessun comando recente</li> : null}
        {props.commands.map((c) => (
          <li key={c.commandId} class={`cmd cmd-${c.status}`}>
            <span class="cmd-status">{statusLabel(c.status)}</span>
            <span class="cmd-name">{commandLabel(c.command)}</span>
            <span class="cmd-value">{c.value !== null && c.value !== undefined ? JSON.stringify(c.value) : ""}</span>
            <span class="cmd-info">{c.error ? c.error.message : c.issuedBy ?? ""}</span>
            <time>{formatAgo(c.updatedAt)}</time>
          </li>
        ))}
      </ul>
    </Section>
  );
}

function statusLabel(status: CommandView["status"]): string {
  switch (status) {
    case "pending":
      return "INVIO";
    case "sent":
      return "INVIATO";
    case "received":
      return "RICEVUTO";
    case "completed":
      return "OK";
    case "failed":
      return "ERRORE";
    case "rejected":
      return "RIFIUTATO";
    case "timeout":
      return "TIMEOUT";
  }
}

function RenameDialog(props: { camera: CameraView; onClose: () => void }) {
  const { store } = useServices();
  const [name, setName] = useState(props.camera.name);
  const [busy, setBusy] = useState(false);
  async function submit(event: Event) {
    event.preventDefault();
    setBusy(true);
    try {
      await api.updateCamera(props.camera.id, { name: name.trim() });
      store.toast("success", "Camera rinominata");
      props.onClose();
    } catch (err) {
      store.toast("error", err instanceof ApiError ? err.message : "Rinomina non riuscita");
    } finally {
      setBusy(false);
    }
  }
  return (
    <Modal title="Rinomina camera" onClose={props.onClose}>
      <form class="form" onSubmit={submit}>
        <label class="field">
          <span>Nome</span>
          <input value={name} maxLength={48} onInput={(e) => setName((e.target as HTMLInputElement).value)} autofocus />
        </label>
        <div class="form-actions">
          <button type="button" class="btn btn-ghost" onClick={props.onClose}>
            Annulla
          </button>
          <button type="submit" class="btn btn-primary" disabled={busy || !name.trim()}>
            Salva
          </button>
        </div>
      </form>
    </Modal>
  );
}

function RevokeDialog(props: { camera: CameraView; onClose: () => void }) {
  const { store, navigate } = useServices();
  const [busy, setBusy] = useState(false);
  async function revoke() {
    setBusy(true);
    try {
      const result = await api.revoke(props.camera.id);
      store.toast("warning", `Dispositivo revocato (live input: ${result.cloudflareAction})`, 8000);
      props.onClose();
      navigate("#/");
    } catch (err) {
      store.toast("error", err instanceof ApiError ? err.message : "Revoca non riuscita");
      setBusy(false);
    }
  }
  return (
    <Modal title="Revoca dispositivo" onClose={props.onClose}>
      <p>
        Revocare <strong>{props.camera.name}</strong>? Il telefono verrà disconnesso, il suo token invalidato e (se configurato) le chiavi del
        live input Cloudflare ruotate. Per riutilizzarlo servirà una nuova associazione.
      </p>
      <div class="form-actions">
        <button type="button" class="btn btn-ghost" onClick={props.onClose}>
          Annulla
        </button>
        <button type="button" class="btn btn-danger" disabled={busy} onClick={() => void revoke()}>
          Revoca
        </button>
      </div>
    </Modal>
  );
}
