import type { CameraView } from "../types";
import { connectionQuality, tallyLabel, tallyState } from "../controls";
import { cameraTitle, cloudflareLabel, formatKbps, networkLabel, slotLabel } from "../format";
import { Dot, Pill } from "./common";

export function batteryText(camera: CameraView): string {
  const battery = camera.telemetry?.battery;
  if (!battery || battery.percent === null) return "—";
  return `${Math.round(battery.percent)}%${battery.charging ? " ⚡" : ""}`;
}

export function CameraTile(props: { camera: CameraView; onOpen: () => void }) {
  const { camera } = props;
  const tally = tallyState(camera);
  const t = camera.telemetry;
  const s = camera.state;
  const quality = connectionQuality(camera);
  const cf = camera.cloudflare.state;
  return (
    <button type="button" class={`tile tally-${tally}`} onClick={props.onOpen} aria-label={cameraTitle(camera.slot, camera.name)}>
      <div class="tile-top">
        <span class="tile-slot">{slotLabel(camera.slot)}</span>
        <Pill tone={tally === "live" ? "red" : tally === "reconnecting" || tally === "paused" || tally === "connecting" ? "amber" : tally === "error" ? "red" : tally === "offline" ? "gray" : "green"} pulse={tally === "live"}>
          {tally === "live" ? "● " : ""}
          {tallyLabel(tally)}
        </Pill>
      </div>
      <div class="tile-name">{camera.name}</div>
      <div class="tile-status">
        <span>
          <Dot tone={camera.online ? "green" : "red"} /> {camera.online ? "ONLINE" : "OFFLINE"}
        </span>
        <span title={cloudflareLabel(cf)}>
          <Dot tone={cf === "live" ? "green" : cf === "reconnecting" ? "amber" : cf === "error" || cf === "disabled" ? "red" : "gray"} /> Cloudflare
        </span>
      </div>
      <dl class="tile-metrics">
        <div>
          <dt>Batteria</dt>
          <dd>{batteryText(camera)}</dd>
        </div>
        <div>
          <dt>Rete</dt>
          <dd>{networkLabel(t?.network.type)}</dd>
        </div>
        <div>
          <dt>Bitrate</dt>
          <dd class={`q-${quality}`}>{t && t.streamStatus === "live" ? formatKbps(t.bitrateKbps) : "—"}</dd>
        </div>
        <div>
          <dt>FPS</dt>
          <dd>{t && t.streamStatus === "live" ? Math.round(t.fps) : s ? s.fps : "—"}</dd>
        </div>
        <div>
          <dt>Risoluzione</dt>
          <dd>{t?.resolution || s?.resolution || "—"}</dd>
        </div>
        <div>
          <dt>Camera</dt>
          <dd>{s ? (s.facing === "front" ? "Frontale" : "Posteriore") : "—"}</dd>
        </div>
      </dl>
      {!camera.activated ? <div class="tile-note">In attesa che il telefono completi l'associazione</div> : null}
    </button>
  );
}

export function EmptyTile(props: { slot: number; onAdd: (slot: number) => void }) {
  return (
    <button type="button" class="tile tile-empty" onClick={() => props.onAdd(props.slot)}>
      <span class="tile-slot">{slotLabel(props.slot)}</span>
      <span class="tile-add">＋ Aggiungi camera</span>
      <span class="tile-note">Associa un telefono con il codice mostrato dall'app</span>
    </button>
  );
}
