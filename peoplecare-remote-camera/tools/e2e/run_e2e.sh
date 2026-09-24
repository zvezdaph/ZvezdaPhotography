#!/usr/bin/env bash
# Local end-to-end check of the control plane, with no Cloudflare account:
#   - Cloudflare Worker + Durable Object in `wrangler dev` (real workerd, SQLite, WebSockets);
#   - Cloudflare Stream API replaced by tools/e2e/mock-cloudflare-api.mjs (MOCK, no video);
#   - Control Room built with Vite and driven in headless Chromium (Playwright);
#   - phone: the real Dart layer of the app (pairing, WebSocket, command guard,
#     executor) with a simulated camera engine (apps/remote_camera/test_e2e).
# Screenshots are written to build/e2e/.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib.sh"

require_node
require_flutter
require_cmd curl "necessario per attendere il Worker"

WORK="$(mktemp -d)"
PORT=8787
MOCK_PORT=8788
PASSWORD="e2e-password-0123456"
PIDS=()
cleanup() {
  for pid in "${PIDS[@]}"; do kill -- "-$pid" 2>/dev/null || kill "$pid" 2>/dev/null || true; done
  rm -rf "$WORK"
}
trap cleanup EXIT

"$ROOT/scripts/build_control_room.sh"
(cd "$ROOT/tools/e2e" && { [[ -d node_modules ]] || npm ci --no-audit --no-fund; })
(cd "$ROOT/cloudflare/worker" && { [[ -d node_modules ]] || npm ci --no-audit --no-fund; })
mkdir -p "$ROOT/build/e2e"

info "Mock dell'API Cloudflare Stream su :$MOCK_PORT"
MOCK_PORT=$MOCK_PORT setsid node "$ROOT/tools/e2e/mock-cloudflare-api.mjs" >"$ROOT/build/e2e/mock-api.log" 2>&1 &
PIDS+=($!)

info "Worker in wrangler dev su :$PORT"
# setsid: wrangler and workerd get their own process group, stopped together by cleanup().
setsid bash -c 'cd "$1" && shift && exec npx wrangler dev "$@"' _ "$ROOT/cloudflare/worker" \
  --ip 127.0.0.1 --port "$PORT" --persist-to "$WORK/state" --show-interactive-dev-session=false \
  --var "CONTROL_ROOM_PASSWORD:$PASSWORD" \
  --var "CLOUDFLARE_ACCOUNT_ID:e2e-account" \
  --var "CLOUDFLARE_API_TOKEN:e2e-api-token" \
  --var "CLOUDFLARE_API_BASE:http://127.0.0.1:$MOCK_PORT/client/v4" \
  --var "CF_POLL_INTERVAL_SECONDS:10" \
  >"$ROOT/build/e2e/wrangler.log" 2>&1 &
PIDS+=($!)
for _ in $(seq 1 120); do
  curl -sf "http://127.0.0.1:$PORT/api/health" >/dev/null 2>&1 && break
  sleep 1
done
curl -sf "http://127.0.0.1:$PORT/api/health" || die "il Worker non risponde (vedi build/e2e/wrangler.log)"
echo

info "Telefono: livello Dart reale dell'app (motore camera simulato)"
(cd "$ROOT/apps/remote_camera" && E2E_SERVER="http://127.0.0.1:$PORT" E2E_CODE_FILE="$WORK/code" \
  E2E_DONE_FILE="$WORK/done" flutter test test_e2e/phone_e2e_test.dart --reporter expanded \
  >"$ROOT/build/e2e/phone.log" 2>&1) &
PHONE_PID=$!

info "Control Room in Chromium (Playwright)"
if ! E2E_BASE="http://127.0.0.1:$PORT" E2E_MOCK_API="http://127.0.0.1:$MOCK_PORT" E2E_PASSWORD="$PASSWORD" \
  E2E_CODE_FILE="$WORK/code" E2E_DONE_FILE="$WORK/done" E2E_SCREENSHOTS="$ROOT/build/e2e" \
  node "$ROOT/tools/e2e/control-room.e2e.mjs"; then
  wait "$PHONE_PID" || true
  cat "$ROOT/build/e2e/phone.log"
  die "scenario della Control Room fallito (screenshot in build/e2e/failure.png)"
fi
if ! wait "$PHONE_PID"; then
  cat "$ROOT/build/e2e/phone.log"
  die "verifiche lato telefono fallite"
fi
grep -E "\[phone\]|All tests passed" "$ROOT/build/e2e/phone.log" || true
info "E2E completato: screenshot in build/e2e/"
