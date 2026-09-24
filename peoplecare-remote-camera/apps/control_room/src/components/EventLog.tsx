import { useMemo, useState } from "preact/hooks";
import type { CameraView, EventView } from "../types";
import { formatTime, slotLabel } from "../format";

export function EventLog(props: { events: EventView[]; title: string; cameras?: CameraView[]; limit?: number }) {
  const [level, setLevel] = useState<"all" | "warning" | "error">("all");
  const names = useMemo(() => {
    const map = new Map<string, string>();
    for (const c of props.cameras ?? []) map.set(c.id, `${slotLabel(c.slot)} ${c.name}`);
    return map;
  }, [props.cameras]);
  const filtered = props.events
    .filter((e) => level === "all" || (level === "warning" ? e.level !== "info" : e.level === "error"))
    .slice(-(props.limit ?? 150))
    .reverse();
  return (
    <section class="panel log-panel">
      <header class="panel-head">
        <h3>{props.title}</h3>
        <div class="segmented" role="group" aria-label="Filtro livello">
          {(["all", "warning", "error"] as const).map((value) => (
            <button type="button" key={value} class={level === value ? "active" : ""} onClick={() => setLevel(value)}>
              {value === "all" ? "Tutti" : value === "warning" ? "Warning+" : "Errori"}
            </button>
          ))}
        </div>
      </header>
      <ol class="log">
        {filtered.length === 0 ? <li class="log-empty">Nessun evento</li> : null}
        {filtered.map((event) => (
          <li key={event.id} class={`log-row log-${event.level}`}>
            <time>{formatTime(event.ts)}</time>
            <span class="log-level">{event.level === "error" ? "ERROR" : event.level === "warning" ? "WARNING" : "INFO"}</span>
            {props.cameras && event.cameraId ? <span class="log-cam">{names.get(event.cameraId) ?? "camera rimossa"}</span> : null}
            <span class="log-msg">{event.message}</span>
          </li>
        ))}
      </ol>
    </section>
  );
}
