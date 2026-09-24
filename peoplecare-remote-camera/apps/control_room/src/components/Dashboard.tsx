import { useState } from "preact/hooks";
import { useAppState, useServices } from "../context";
import { camerasBySlot } from "../store";
import { CameraTile, EmptyTile } from "./CameraTile";
import { AddCameraDialog } from "./AddCameraDialog";
import { EventLog } from "./EventLog";

const DEFAULT_SLOTS = 4;

export function Dashboard() {
  const { navigate } = useServices();
  const cameras = useAppState((s) => camerasBySlot(s));
  const events = useAppState((s) => s.events);
  const [addSlot, setAddSlot] = useState<number | null>(null);

  const usedSlots = new Set(cameras.map((c) => c.slot));
  const maxSlot = Math.max(DEFAULT_SLOTS, ...cameras.map((c) => c.slot));
  const slots: number[] = [];
  for (let slot = 1; slot <= maxSlot; slot++) slots.push(slot);

  return (
    <main class="dashboard">
      <div class="dashboard-head">
        <h1>Multicamera</h1>
        <button type="button" class="btn btn-primary" onClick={() => setAddSlot(slots.find((s) => !usedSlots.has(s)) ?? maxSlot + 1)}>
          ＋ Aggiungi camera
        </button>
      </div>
      <div class="grid">
        {slots.map((slot) => {
          const camera = cameras.find((c) => c.slot === slot);
          return camera ? (
            <CameraTile key={camera.id} camera={camera} onOpen={() => navigate(`#/camera/${camera.id}`)} />
          ) : (
            <EmptyTile key={`empty-${slot}`} slot={slot} onAdd={setAddSlot} />
          );
        })}
      </div>
      <EventLog events={events} title="Ultimi eventi" cameras={cameras} />
      {addSlot !== null ? <AddCameraDialog initialSlot={addSlot} onClose={() => setAddSlot(null)} /> : null}
    </main>
  );
}
