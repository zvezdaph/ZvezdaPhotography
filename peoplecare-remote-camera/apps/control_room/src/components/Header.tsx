import { useAppState, useServices, useTick } from "../context";
import { Dot } from "./common";

export function Header() {
  const { navigate, logout } = useServices();
  const connection = useAppState((s) => s.connection);
  const operator = useAppState((s) => s.auth.operator);
  const offset = useAppState((s) => s.serverOffsetMs);
  const config = useAppState((s) => s.config);
  const now = useTick(1000);
  const time = new Date(now + offset).toLocaleTimeString("it-IT", { hour12: false });
  const tone = connection === "online" ? "green" : connection === "connecting" ? "amber" : "red";
  const label = connection === "online" ? "Control plane online" : connection === "connecting" ? "Connessione…" : "Control plane offline";
  return (
    <header class="topbar">
      <button type="button" class="brand" onClick={() => navigate("#/")}>
        <span class="brand-mark" aria-hidden="true" />
        <span class="brand-name">PeopleCareTV</span>
        <span class="brand-sub">REGIA</span>
      </button>
      <div class="topbar-center">
        <span class="clock" title="Ora del server">{time}</span>
      </div>
      <div class="topbar-right">
        {config && !config.streamConfigured ? (
          <span class="warn-chip" title="Imposta CLOUDFLARE_ACCOUNT_ID e CLOUDFLARE_API_TOKEN come Wrangler secrets">
            Cloudflare Stream non configurato
          </span>
        ) : null}
        <span class="conn">
          <Dot tone={tone} /> {label}
        </span>
        <span class="operator">{operator ?? ""}</span>
        <button type="button" class="btn btn-ghost" onClick={() => void logout()}>
          Esci
        </button>
      </div>
    </header>
  );
}
