#!/usr/bin/env bash
# Builds the Control Room, tests the Worker and deploys both to Cloudflare.
#
# Prerequisites (docs/CLOUDFLARE_SETUP.md):
#   - `npx wrangler login` done (or CLOUDFLARE_API_TOKEN of a deploy token exported)
#   - Worker secrets set: CLOUDFLARE_ACCOUNT_ID, CLOUDFLARE_API_TOKEN, CONTROL_ROOM_PASSWORD
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_node
"$ROOT/scripts/build_control_room.sh"

cd "$ROOT/cloudflare/worker"
[[ -d node_modules ]] || npm ci --no-audit --no-fund
info "Worker: typecheck e test"
npm run typecheck
npm test
info "Worker: verifica configurazione (dry run)"
npx wrangler deploy --dry-run --outdir "$ROOT/build/worker-dry-run"
info "Deploy su Cloudflare"
npx wrangler deploy
info "Fatto. Controlla https://<nome-worker>.<sottodominio>.workers.dev/api/health (streamConfigured deve essere true)"
