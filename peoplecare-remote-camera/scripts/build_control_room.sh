#!/usr/bin/env bash
# Type-checks, tests and builds the Control Room into apps/control_room/dist
# (served by the Worker as static assets).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_node
cd "$ROOT/apps/control_room"
if [[ ! -d node_modules/livekit-client ]]; then
  npm install --no-audit --no-fund
fi
info "Typecheck"
npm run typecheck
info "Test"
npm test
info "Build"
npx vite build
info "Control Room pronta in apps/control_room/dist ($(du -sh dist | cut -f1))"
