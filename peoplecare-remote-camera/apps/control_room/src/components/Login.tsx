import { useState } from "preact/hooks";
import { api, ApiError } from "../api";

export function Login(props: { loginConfigured: boolean; onLoggedIn: (operator: string) => void }) {
  const [password, setPassword] = useState("");
  const [operator, setOperator] = useState(() => localStorage.getItem("pcrc.operator") ?? "Regia");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function submit(event: Event) {
    event.preventDefault();
    setBusy(true);
    setError(null);
    try {
      const result = await api.login(password, operator.trim() || "Regia");
      localStorage.setItem("pcrc.operator", result.operator);
      setPassword("");
      props.onLoggedIn(result.operator);
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "Accesso non riuscito");
    } finally {
      setBusy(false);
    }
  }

  return (
    <div class="login-screen">
      <form class="login-card" onSubmit={submit}>
        <div class="brand brand-large">
          <span class="brand-mark" aria-hidden="true" />
          <div>
            <div class="brand-name">PeopleCareTV</div>
            <div class="brand-sub">Remote Camera · Regia</div>
          </div>
        </div>
        {!props.loginConfigured ? (
          <p class="notice notice-error">
            Il server non ha una password di regia configurata. Imposta il secret <code>CONTROL_ROOM_PASSWORD</code> (minimo 12
            caratteri) con <code>wrangler secret put</code>.
          </p>
        ) : null}
        <label class="field">
          <span>Operatore</span>
          <input value={operator} maxLength={32} onInput={(e) => setOperator((e.target as HTMLInputElement).value)} autocomplete="username" />
        </label>
        <label class="field">
          <span>Password regia</span>
          <input
            type="password"
            value={password}
            onInput={(e) => setPassword((e.target as HTMLInputElement).value)}
            autocomplete="current-password"
            required
            autofocus
          />
        </label>
        {error ? <p class="notice notice-error">{error}</p> : null}
        <button class="btn btn-primary btn-big" type="submit" disabled={busy || !password}>
          {busy ? "Accesso…" : "Entra in regia"}
        </button>
      </form>
    </div>
  );
}
