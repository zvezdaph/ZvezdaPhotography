export function slotLabel(slot: number): string {
  return `CAM ${String(slot).padStart(2, "0")}`;
}

/** "CAM 01 - SALA" stays as is; a name without the slot gets it as prefix ("CAM 02 Palco"). */
export function cameraTitle(slot: number, name: string): string {
  const label = slotLabel(slot);
  return name.toUpperCase().startsWith(label) ? name : `${label} ${name}`;
}

export function formatKbps(kbps: number | null | undefined): string {
  if (kbps === null || kbps === undefined || !Number.isFinite(kbps)) return "—";
  if (kbps >= 1000) return `${(kbps / 1000).toFixed(kbps >= 10_000 ? 0 : 1)} Mbps`;
  return `${Math.round(kbps)} kbps`;
}

export function formatDuration(totalSeconds: number | null | undefined): string {
  if (totalSeconds === null || totalSeconds === undefined || !Number.isFinite(totalSeconds) || totalSeconds < 0) return "—";
  const s = Math.floor(totalSeconds);
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  const sec = s % 60;
  const mm = String(m).padStart(2, "0");
  const ss = String(sec).padStart(2, "0");
  return h > 0 ? `${h}:${mm}:${ss}` : `${mm}:${ss}`;
}

export function formatBytes(bytes: number | null | undefined): string {
  if (bytes === null || bytes === undefined || !Number.isFinite(bytes)) return "—";
  const units = ["B", "KB", "MB", "GB", "TB"];
  let value = bytes;
  let unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return `${value.toFixed(value >= 100 || unit === 0 ? 0 : 1)} ${units[unit]}`;
}

export function formatTime(ts: number): string {
  const d = new Date(ts);
  return d.toLocaleTimeString("it-IT", { hour12: false });
}

export function formatAgo(ts: number | null | undefined, now = Date.now()): string {
  if (!ts) return "mai";
  const diff = Math.max(0, Math.round((now - ts) / 1000));
  if (diff < 5) return "adesso";
  if (diff < 60) return `${diff}s fa`;
  if (diff < 3600) return `${Math.floor(diff / 60)} min fa`;
  if (diff < 86400) return `${Math.floor(diff / 3600)} h fa`;
  return `${Math.floor(diff / 86400)} g fa`;
}

export function networkLabel(type: string | undefined | null): string {
  switch (type) {
    case "wifi":
      return "Wi-Fi";
    case "cellular":
      return "Rete mobile";
    case "ethernet":
      return "Ethernet";
    case "vpn":
      return "VPN";
    case "none":
      return "Nessuna rete";
    case "other":
      return "Altra rete";
    default:
      return "—";
  }
}

export function cloudflareLabel(state: string): string {
  switch (state) {
    case "live":
      return "Ingest attivo";
    case "reconnecting":
      return "Ingest in riconnessione";
    case "offline":
      return "Nessun flusso";
    case "disabled":
      return "Live input disabilitato";
    case "error":
      return "Errore ingest";
    case "unconfigured":
      return "Non configurato";
    default:
      return "Stato sconosciuto";
  }
}

export function commandLabel(command: string | null | undefined): string {
  const labels: Record<string, string> = {
    start_stream: "Avvio stream",
    stop_stream: "Stop stream",
    pause: "Pausa",
    resume: "Ripresa",
    restart_stream: "Riavvio stream",
    reconnect: "Riconnessione",
    switch_camera: "Cambio camera",
    set_zoom: "Zoom",
    zoom_in: "Zoom +",
    zoom_out: "Zoom -",
    set_audio_enabled: "Microfono",
    set_video_enabled: "Video",
    set_torch: "Torcia",
    set_autofocus: "Autofocus",
    focus_point: "Punto di fuoco",
    set_exposure: "Esposizione",
    set_resolution: "Risoluzione",
    set_fps: "FPS",
    set_bitrate: "Bitrate",
    set_preset: "Preset",
    set_record: "Registrazione",
  };
  return (command && labels[command]) || command || "Comando";
}
