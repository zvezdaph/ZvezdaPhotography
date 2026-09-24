#!/usr/bin/env bash
# Shared helpers for the scripts in this directory (sourced, not executed).

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export ROOT

info() { printf '\033[1;34m[INFO]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*" >&2; }
die() {
  printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2
  exit 1
}

# env_get KEY [DEFAULT]: value of KEY from the environment, else from $ROOT/.env
# (the file is parsed, never sourced), else DEFAULT.
env_get() {
  local key="$1" default="${2:-}" value=""
  if [[ -n "${!key:-}" ]]; then
    printf '%s' "${!key}"
    return
  fi
  if [[ -f "$ROOT/.env" ]]; then
    value="$(sed -n "s/^${key}=//p" "$ROOT/.env" | tail -n 1)"
    value="${value%\"}"
    value="${value#\"}"
  fi
  printf '%s' "${value:-$default}"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "$1 non trovato: $2"
}

require_node() {
  require_cmd node "installa Node.js 22 o superiore (https://nodejs.org)"
  require_cmd npm "installa npm (incluso in Node.js)"
  node -e 'process.exit(Number(process.versions.node.split(".")[0]) >= 22 ? 0 : 1)' ||
    die "Node.js $(node --version) troppo vecchio: serve la versione 22 o superiore"
}

require_flutter() {
  require_cmd flutter "installa Flutter stable (https://docs.flutter.dev/get-started/install/linux/android)"
}
