#!/usr/bin/env bash
# Runs every automated check of the repository:
#   Worker (tsc + vitest in workerd), Control Room (tsc + vitest + vite build),
#   Android app (flutter analyze + flutter test) and, with --native, the
#   compile check of the Kotlin sources (scripts/check_android_sources.sh).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

NATIVE=false
[[ "${1:-}" == "--native" ]] && NATIVE=true
require_node

info "== Cloudflare Worker"
(cd "$ROOT/cloudflare/worker" && { [[ -d node_modules ]] || npm ci --no-audit --no-fund; } && npm run typecheck && npm test)

info "== Control Room"
"$ROOT/scripts/build_control_room.sh"

if command -v flutter >/dev/null 2>&1; then
  info "== App Android (Dart)"
  (cd "$ROOT/apps/remote_camera" && flutter pub get && flutter analyze && flutter test)
else
  warn "Flutter non trovato: test Dart saltati"
fi

if [[ "$NATIVE" == true ]]; then
  info "== Sorgenti Kotlin (compilazione di verifica)"
  "$ROOT/scripts/check_android_sources.sh"
fi
info "Tutti i controlli completati con successo"
