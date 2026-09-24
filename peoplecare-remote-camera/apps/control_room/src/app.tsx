import { useEffect, useMemo, useState } from "preact/hooks";
import { api } from "./api";
import { CommandSender } from "./commands";
import { ServicesContext, useAppState } from "./context";
import type { Services } from "./context";
import { commandLabel } from "./format";
import { ControlSocket } from "./socket";
import { applyServerMessage, Store } from "./store";
import type { Route } from "./store";
import { CameraDetail } from "./components/CameraDetail";
import { Dashboard } from "./components/Dashboard";
import { Header } from "./components/Header";
import { Login } from "./components/Login";

function parseRoute(hash: string): Route {
  const match = /^#\/camera\/([A-Za-z0-9_-]{8,64})$/.exec(hash);
  return match ? { name: "camera", cameraId: match[1] } : { name: "dashboard" };
}

export function App() {
  const services = useMemo<Services>(() => {
    const store = new Store();
    let authCheck: ReturnType<typeof setTimeout> | null = null;
    const socket = new ControlSocket({
      onMessage: (message) => {
        store.set((s) => applyServerMessage(s, message));
        if (message.type === "command_status" && ["failed", "rejected", "timeout"].includes(String(message.status))) {
          const error = message.error as { message?: string } | undefined;
          store.toast("error", `${commandLabel(message.command as string)}: ${error?.message ?? message.status}`);
        }
      },
      onStatus: (status) => {
        store.set((s) => ({ ...s, connection: status }));
        if (status === "offline" && !authCheck) {
          // A refused upgrade (expired session) looks like a network error: verify the session.
          authCheck = setTimeout(async () => {
            authCheck = null;
            try {
              const me = await api.me();
              if (!me.authenticated) {
                socket.stop();
                store.set((s) => ({ ...s, auth: { ...s.auth, status: "anonymous" }, connection: "idle" }));
              }
            } catch {
              // server unreachable: keep retrying through the socket backoff
            }
          }, 1500);
        }
      },
      onUnauthorized: () => {
        socket.stop();
        store.set((s) => ({ ...s, auth: { ...s.auth, status: "anonymous" }, connection: "idle" }));
        store.toast("warning", "Sessione scaduta: accedi di nuovo");
      },
    });
    const sender = new CommandSender(store, socket);
    return {
      store,
      socket,
      sender,
      navigate: (hash: string) => {
        if (window.location.hash !== hash) window.location.hash = hash;
        store.set((s) => ({ ...s, route: parseRoute(hash) }));
      },
      logout: async () => {
        try {
          await api.logout();
        } finally {
          socket.stop();
          store.set((s) => ({ ...s, auth: { status: "anonymous", operator: null, loginConfigured: s.auth.loginConfigured }, connection: "idle", cameras: {} }));
        }
      },
    };
  }, []);

  const { store, socket } = services;
  const [, setTick] = useState(0);
  useEffect(() => store.subscribe(() => setTick((x) => x + 1)), [store]);

  useEffect(() => {
    const onHash = () => store.set((s) => ({ ...s, route: parseRoute(window.location.hash) }));
    onHash();
    window.addEventListener("hashchange", onHash);
    const onOnline = () => socket.reconnectNow();
    window.addEventListener("online", onOnline);
    void api
      .me()
      .then((me) => {
        store.set((s) => ({
          ...s,
          auth: { status: me.authenticated ? "authenticated" : "anonymous", operator: me.operator, loginConfigured: me.loginConfigured },
        }));
        if (me.authenticated) socket.start();
      })
      .catch(() => {
        store.set((s) => ({ ...s, auth: { ...s.auth, status: "anonymous" } }));
        store.toast("error", "Server regia non raggiungibile");
      });
    return () => {
      window.removeEventListener("hashchange", onHash);
      window.removeEventListener("online", onOnline);
      socket.stop();
    };
  }, [store, socket]);

  const state = store.get();
  return (
    <ServicesContext.Provider value={services}>
      {state.auth.status === "unknown" ? (
        <div class="splash">Connessione alla regia…</div>
      ) : state.auth.status === "anonymous" ? (
        <Login
          loginConfigured={state.auth.loginConfigured}
          onLoggedIn={(operator) => {
            store.set((s) => ({ ...s, auth: { ...s.auth, status: "authenticated", operator } }));
            socket.start();
          }}
        />
      ) : (
        <div class="shell">
          <Header />
          {state.route.name === "camera" ? <CameraDetail cameraId={state.route.cameraId} /> : <Dashboard />}
        </div>
      )}
      <Toasts />
    </ServicesContext.Provider>
  );
}

function Toasts() {
  const toasts = useAppState((s) => s.toasts);
  return (
    <div class="toasts" role="status" aria-live="polite">
      {toasts.map((t) => (
        <div key={t.id} class={`toast toast-${t.level}`}>
          {t.message}
        </div>
      ))}
    </div>
  );
}
