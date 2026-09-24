#!/usr/bin/env bash
# Installs the dependencies of every component and prepares the local
# configuration files. Safe to run more than once.
#
# Usage: scripts/setup.sh [--skip-android]
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

SKIP_ANDROID=false
[[ "${1:-}" == "--skip-android" ]] && SKIP_ANDROID=true

require_node
info "Node.js $(node --version), npm $(npm --version)"

info "Cloudflare Worker: npm ci"
(cd "$ROOT/cloudflare/worker" && npm ci --no-audit --no-fund)

info "Control Room: npm ci"
(cd "$ROOT/apps/control_room" && npm ci --no-audit --no-fund)

if [[ "$SKIP_ANDROID" == false ]]; then
  if command -v flutter >/dev/null 2>&1; then
    info "App Android: flutter pub get ($(flutter --version | head -n 1))"
    (cd "$ROOT/apps/remote_camera" && flutter pub get)
    if ! command -v java >/dev/null 2>&1; then
      warn "java non trovato: per compilare l'APK serve un JDK 17 o superiore"
    fi
    if [[ -z "${ANDROID_HOME:-}${ANDROID_SDK_ROOT:-}" ]] && ! flutter config --list 2>/dev/null | grep -q "android-sdk"; then
      warn "Android SDK non configurato: vedi docs/ANDROID_SETUP.md"
    fi
  else
    warn "Flutter non trovato: salto l'app Android (vedi docs/ANDROID_SETUP.md)"
  fi
fi

if [[ ! -f "$ROOT/cloudflare/worker/.dev.vars" ]]; then
  cp "$ROOT/cloudflare/worker/.dev.vars.example" "$ROOT/cloudflare/worker/.dev.vars"
  info "Creato cloudflare/worker/.dev.vars dai placeholder: inserisci i tuoi valori per 'wrangler dev'"
fi
if [[ ! -f "$ROOT/.env" ]]; then
  cp "$ROOT/.env.example" "$ROOT/.env"
  info "Creato .env dai placeholder: imposta CONTROL_PLANE_URL prima di compilare l'APK"
fi

info "Setup completato. Prossimi passi: docs/CLOUDFLARE_SETUP.md, poi scripts/deploy_cloudflare.sh e scripts/build_android.sh"
