import type { ComponentChildren } from "preact";
import type { CommandView } from "../types";

export function Pill(props: { tone: "red" | "green" | "amber" | "gray" | "blue"; children: ComponentChildren; pulse?: boolean; title?: string }) {
  return (
    <span class={`pill pill-${props.tone}${props.pulse ? " pulse" : ""}`} title={props.title}>
      {props.children}
    </span>
  );
}

export function Dot(props: { tone: "red" | "green" | "amber" | "gray" | "blue"; title?: string }) {
  return <span class={`dot dot-${props.tone}`} title={props.title} aria-hidden="true" />;
}

export function Section(props: { title: string; children: ComponentChildren; actions?: ComponentChildren }) {
  return (
    <section class="panel">
      <header class="panel-head">
        <h3>{props.title}</h3>
        {props.actions ? <div class="panel-actions">{props.actions}</div> : null}
      </header>
      <div class="panel-body">{props.children}</div>
    </section>
  );
}

/** Button bound to a command: shows the real ACK lifecycle of the last command it sent. */
export function CommandButton(props: {
  label: string;
  onClick: () => void;
  disabled?: boolean;
  title?: string;
  variant?: "primary" | "danger" | "live" | "ghost" | "active";
  last?: CommandView | null;
  big?: boolean;
}) {
  const pending = props.last && ["pending", "sent", "received"].includes(props.last.status);
  const failed = props.last && ["failed", "rejected", "timeout"].includes(props.last.status) && Date.now() - props.last.updatedAt < 8000;
  const classes = ["btn", `btn-${props.variant ?? "ghost"}`];
  if (props.big) classes.push("btn-big");
  if (pending) classes.push("is-pending");
  if (failed) classes.push("is-failed");
  return (
    <button
      type="button"
      class={classes.join(" ")}
      disabled={props.disabled || Boolean(pending)}
      title={failed ? props.last?.error?.message ?? "Comando fallito" : props.title}
      onClick={props.onClick}
    >
      {pending ? <span class="spinner" aria-hidden="true" /> : null}
      {props.label}
    </button>
  );
}

export function Metric(props: { label: string; value: ComponentChildren; tone?: "red" | "green" | "amber" | "gray" }) {
  return (
    <div class={`metric${props.tone ? ` metric-${props.tone}` : ""}`}>
      <span class="metric-label">{props.label}</span>
      <span class="metric-value">{props.value}</span>
    </div>
  );
}

export function Modal(props: { title: string; onClose: () => void; children: ComponentChildren; wide?: boolean }) {
  return (
    <div class="modal-backdrop" role="presentation" onClick={(e) => e.target === e.currentTarget && props.onClose()}>
      <div class={`modal${props.wide ? " modal-wide" : ""}`} role="dialog" aria-modal="true" aria-label={props.title}>
        <header class="modal-head">
          <h2>{props.title}</h2>
          <button type="button" class="btn btn-ghost" onClick={props.onClose} aria-label="Chiudi">
            ✕
          </button>
        </header>
        <div class="modal-body">{props.children}</div>
      </div>
    </div>
  );
}
