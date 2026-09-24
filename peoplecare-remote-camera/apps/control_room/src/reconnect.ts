/**
 * Exponential backoff with full jitter, shared by the Control Room WebSocket.
 * The same policy (same parameters) is implemented in the Android app.
 */
export interface BackoffOptions {
  initialMs: number;
  maxMs: number;
  multiplier: number;
  /** 0 = no jitter, 1 = delay picked uniformly in [delay/2, delay]. */
  jitter: number;
}

export const DEFAULT_BACKOFF: BackoffOptions = { initialMs: 1000, maxMs: 30_000, multiplier: 2, jitter: 0.5 };

export class ReconnectPolicy {
  private attempt = 0;

  constructor(
    private readonly options: BackoffOptions = DEFAULT_BACKOFF,
    private readonly random: () => number = Math.random,
  ) {}

  get attempts(): number {
    return this.attempt;
  }

  /** Delay before the next attempt; increments the attempt counter. */
  nextDelayMs(): number {
    const { initialMs, maxMs, multiplier, jitter } = this.options;
    const base = Math.min(maxMs, initialMs * Math.pow(multiplier, this.attempt));
    this.attempt++;
    const spread = base * jitter * this.random();
    return Math.round(base - spread);
  }

  reset(): void {
    this.attempt = 0;
  }
}
