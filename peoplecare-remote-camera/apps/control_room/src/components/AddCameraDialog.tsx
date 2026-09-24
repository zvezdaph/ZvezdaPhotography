import { useState } from "preact/hooks";
import { formatPairingCode, isValidPairingCode, normalizePairingCode } from "@protocol";
import { api, ApiError } from "../api";
import { useAppState, useServices } from "../context";
import { freeSlots } from "../store";
import { slotLabel } from "../format";
import { Modal } from "./common";
import { QrScanner } from "./QrScanner";

const NAME_HINTS = ["SALA", "INTERVISTA", "MOBILE", "PALCO", "REGIA", "PUBBLICO"];

export function AddCameraDialog(props: { initialSlot: number; onClose: () => void }) {
  const { store, navigate } = useServices();
  const maxSlots = useAppState((s) => s.config?.maxSlots ?? 16);
  const slots = useAppState((s) => freeSlots(s, maxSlots));
  const [code, setCode] = useState("");
  const [slot, setSlot] = useState(slots.includes(props.initialSlot) ? props.initialSlot : slots[0] ?? 1);
  const [name, setName] = useState("");
  const [scanning, setScanning] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const normalized = normalizePairingCode(code);
  const codeValid = isValidPairingCode(normalized);
  const finalName = name.trim() || `${slotLabel(slot)}`;

  async function submit(event: Event) {
    event.preventDefault();
    if (!codeValid) return;
    setBusy(true);
    setError(null);
    try {
      const result = await api.claim(normalized, finalName, slot);
      store.toast("success", `${slotLabel(slot)} associata: ${result.camera.name}`);
      if (result.warning) store.toast("warning", result.warning, 10_000);
      props.onClose();
      navigate(`#/camera/${result.camera.id}`);
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "Associazione non riuscita");
    } finally {
      setBusy(false);
    }
  }

  return (
    <Modal title="Aggiungi camera" onClose={props.onClose}>
      <form class="form" onSubmit={submit}>
        <ol class="steps">
          <li>Sul telefono apri <strong>PeopleCare Remote Camera</strong> e tocca <strong>ASSOCIA ALLA REGIA</strong>.</li>
          <li>Inserisci qui il codice (o scansiona il QR con la webcam) e assegna nome e slot.</li>
        </ol>
        {scanning ? (
          <QrScanner
            onCode={(value) => {
              setCode(formatPairingCode(value));
              setScanning(false);
            }}
            onClose={() => setScanning(false)}
          />
        ) : (
          <div class="code-row">
            <label class="field grow">
              <span>Codice dispositivo</span>
              <input
                class="code-input"
                value={code}
                placeholder="XXXX-XXXX"
                maxLength={9}
                autocomplete="off"
                spellcheck={false}
                onInput={(e) => {
                  const raw = normalizePairingCode((e.target as HTMLInputElement).value).slice(0, 8);
                  setCode(raw.length > 4 ? `${raw.slice(0, 4)}-${raw.slice(4)}` : raw);
                }}
                autofocus
              />
            </label>
            <button type="button" class="btn btn-ghost" onClick={() => setScanning(true)}>
              Scansiona QR
            </button>
          </div>
        )}
        <div class="form-row">
          <label class="field">
            <span>Slot</span>
            <select value={slot} onChange={(e) => setSlot(Number((e.target as HTMLSelectElement).value))}>
              {slots.map((s) => (
                <option key={s} value={s}>
                  {slotLabel(s)}
                </option>
              ))}
            </select>
          </label>
          <label class="field grow">
            <span>Nome camera</span>
            <input
              value={name}
              maxLength={48}
              placeholder={`${slotLabel(slot)} - SALA`}
              onInput={(e) => setName((e.target as HTMLInputElement).value)}
            />
          </label>
        </div>
        <div class="chips">
          {NAME_HINTS.map((hint) => (
            <button type="button" class="chip" key={hint} onClick={() => setName(`${slotLabel(slot)} - ${hint}`)}>
              {hint}
            </button>
          ))}
        </div>
        {error ? <p class="notice notice-error">{error}</p> : null}
        <div class="form-actions">
          <button type="button" class="btn btn-ghost" onClick={props.onClose}>
            Annulla
          </button>
          <button type="submit" class="btn btn-primary" disabled={!codeValid || busy || slots.length === 0}>
            {busy ? "Associazione…" : "Associa camera"}
          </button>
        </div>
      </form>
    </Modal>
  );
}
