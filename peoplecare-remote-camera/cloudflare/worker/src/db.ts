/**
 * SQLite schema of the Studio Durable Object and typed row accessors.
 * Secrets (device tokens, session tokens, pairing codes) are stored only as SHA-256 hashes.
 */

export const SCHEMA_VERSION = 1;

export const SCHEMA_SQL = `
CREATE TABLE IF NOT EXISTS meta (
  key TEXT PRIMARY KEY,
  value TEXT
);
CREATE TABLE IF NOT EXISTS cameras (
  id TEXT PRIMARY KEY,
  slot INTEGER NOT NULL,
  name TEXT NOT NULL,
  device_token_hash TEXT,
  created_at INTEGER NOT NULL,
  activated_at INTEGER,
  device_model TEXT,
  app_version TEXT,
  os_version TEXT,
  live_input_id TEXT,
  last_seen_at INTEGER,
  state_json TEXT,
  telemetry_json TEXT,
  capabilities_json TEXT,
  cf_status TEXT,
  cf_state TEXT,
  cf_status_at INTEGER,
  cf_error TEXT,
  cmd_seq INTEGER NOT NULL DEFAULT 0
);
CREATE UNIQUE INDEX IF NOT EXISTS cameras_token ON cameras(device_token_hash);
CREATE INDEX IF NOT EXISTS cameras_live_input ON cameras(live_input_id);
CREATE TABLE IF NOT EXISTS pairings (
  id TEXT PRIMARY KEY,
  code_hash TEXT NOT NULL UNIQUE,
  poll_hash TEXT NOT NULL,
  device_name TEXT,
  model TEXT,
  app_version TEXT,
  created_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL,
  claimed_at INTEGER,
  camera_id TEXT,
  issued_at INTEGER
);
CREATE TABLE IF NOT EXISTS sessions (
  token_hash TEXT PRIMARY KEY,
  operator TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  ts INTEGER NOT NULL,
  camera_id TEXT,
  level TEXT NOT NULL,
  source TEXT NOT NULL,
  message TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS events_camera ON events(camera_id, id);
CREATE TABLE IF NOT EXISTS commands (
  command_id TEXT PRIMARY KEY,
  camera_id TEXT NOT NULL,
  command TEXT NOT NULL,
  value_json TEXT,
  issued_by TEXT NOT NULL,
  issued_at INTEGER NOT NULL,
  sent_at INTEGER,
  seq INTEGER,
  status TEXT NOT NULL,
  result_json TEXT,
  error_json TEXT,
  updated_at INTEGER NOT NULL,
  deadline INTEGER
);
CREATE INDEX IF NOT EXISTS commands_pending ON commands(status, deadline);
CREATE TABLE IF NOT EXISTS rate_limits (
  key TEXT PRIMARY KEY,
  window_start INTEGER NOT NULL,
  count INTEGER NOT NULL
);
`;

export interface CameraRow {
  id: string;
  slot: number;
  name: string;
  device_token_hash: string | null;
  created_at: number;
  activated_at: number | null;
  device_model: string | null;
  app_version: string | null;
  os_version: string | null;
  live_input_id: string | null;
  last_seen_at: number | null;
  state_json: string | null;
  telemetry_json: string | null;
  capabilities_json: string | null;
  cf_status: string | null;
  cf_state: string | null;
  cf_status_at: number | null;
  cf_error: string | null;
  cmd_seq: number;
}

export interface PairingRow {
  id: string;
  code_hash: string;
  poll_hash: string;
  device_name: string | null;
  model: string | null;
  app_version: string | null;
  created_at: number;
  expires_at: number;
  claimed_at: number | null;
  camera_id: string | null;
  issued_at: number | null;
}

export interface SessionRow {
  token_hash: string;
  operator: string;
  created_at: number;
  expires_at: number;
}

export interface EventRow {
  id: number;
  ts: number;
  camera_id: string | null;
  level: string;
  source: string;
  message: string;
}

export interface CommandRow {
  command_id: string;
  camera_id: string;
  command: string;
  value_json: string | null;
  issued_by: string;
  issued_at: number;
  sent_at: number | null;
  seq: number | null;
  status: string;
  result_json: string | null;
  error_json: string | null;
  updated_at: number;
  deadline: number | null;
}

type Row = Record<string, SqlStorageValue>;

export class Db {
  constructor(private readonly sql: SqlStorage) {}

  migrate(): void {
    this.sql.exec(SCHEMA_SQL);
    this.sql.exec(
      "INSERT INTO meta (key, value) VALUES ('schema_version', ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
      String(SCHEMA_VERSION),
    );
  }

  all<T>(query: string, ...bindings: unknown[]): T[] {
    return this.sql.exec<Row>(query, ...bindings).toArray() as unknown as T[];
  }

  first<T>(query: string, ...bindings: unknown[]): T | null {
    const rows = this.all<T>(query, ...bindings);
    return rows.length > 0 ? rows[0] : null;
  }

  run(query: string, ...bindings: unknown[]): number {
    const cursor = this.sql.exec(query, ...bindings);
    // Consume the cursor so rowsWritten is final.
    cursor.toArray();
    return cursor.rowsWritten;
  }

  getMeta(key: string): string | null {
    return this.first<{ value: string | null }>("SELECT value FROM meta WHERE key = ?", key)?.value ?? null;
  }

  setMeta(key: string, value: string): void {
    this.run(
      "INSERT INTO meta (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
      key,
      value,
    );
  }

  camera(id: string): CameraRow | null {
    return this.first<CameraRow>("SELECT * FROM cameras WHERE id = ?", id);
  }

  cameras(): CameraRow[] {
    return this.all<CameraRow>("SELECT * FROM cameras ORDER BY slot ASC, created_at ASC");
  }

  cameraByTokenHash(hash: string): CameraRow | null {
    return this.first<CameraRow>("SELECT * FROM cameras WHERE device_token_hash = ?", hash);
  }

  cameraByLiveInput(liveInputId: string): CameraRow | null {
    return this.first<CameraRow>("SELECT * FROM cameras WHERE live_input_id = ?", liveInputId);
  }

  /**
   * Fixed window counter. Returns false when the limit is exceeded.
   * Strongly consistent because the Durable Object is single threaded.
   */
  hit(key: string, limit: number, windowMs: number, now: number): boolean {
    const row = this.first<{ window_start: number; count: number }>(
      "SELECT window_start, count FROM rate_limits WHERE key = ?",
      key,
    );
    if (!row || now - row.window_start >= windowMs) {
      this.run(
        "INSERT INTO rate_limits (key, window_start, count) VALUES (?, ?, 1) ON CONFLICT(key) DO UPDATE SET window_start = excluded.window_start, count = 1",
        key,
        now,
      );
      return true;
    }
    if (row.count >= limit) return false;
    this.run("UPDATE rate_limits SET count = count + 1 WHERE key = ?", key);
    return true;
  }
}

export function parseJson<T>(value: string | null | undefined): T | null {
  if (!value) return null;
  try {
    return JSON.parse(value) as T;
  } catch {
    return null;
  }
}
