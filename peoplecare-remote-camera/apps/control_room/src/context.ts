import { createContext } from "preact";
import { useContext, useEffect, useReducer, useState } from "preact/hooks";
import type { AppState, Store } from "./store";
import type { CommandSender } from "./commands";
import type { ControlSocket } from "./socket";

export interface Services {
  store: Store;
  sender: CommandSender;
  socket: ControlSocket;
  navigate: (hash: string) => void;
  logout: () => Promise<void>;
}

export const ServicesContext = createContext<Services | null>(null);

export function useServices(): Services {
  const services = useContext(ServicesContext);
  if (!services) throw new Error("ServicesContext missing");
  return services;
}

/**
 * Subscribes the component to the store and returns the selected slice.
 * The selector runs on every render, so it may depend on props.
 */
export function useAppState<T>(selector: (state: AppState) => T): T {
  const { store } = useServices();
  const [, force] = useReducer((x: number) => x + 1, 0);
  useEffect(() => store.subscribe(() => force(0)), [store]);
  return selector(store.get());
}

/** Re-renders every `intervalMs` (clocks, "x seconds ago"). */
export function useTick(intervalMs = 1000): number {
  const [now, setNow] = useState(Date.now());
  useEffect(() => {
    const timer = setInterval(() => setNow(Date.now()), intervalMs);
    return () => clearInterval(timer);
  }, [intervalMs]);
  return now;
}
