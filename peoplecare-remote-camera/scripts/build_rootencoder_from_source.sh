#!/usr/bin/env bash
# Builds RootEncoder 2.8.1 from source into a local Maven repository.
#
# Use it only when jitpack.io (which normally serves RootEncoder) is not
# reachable. It still needs Google Maven (dl.google.com), the Gradle plugin
# portal and Maven Central, like any Android library build, and a JDK 17
# (RootEncoder sets jvmToolchain(17)). Then build the app with:
#
#   ROOTENCODER_MAVEN_REPO=<output dir> scripts/build_android.sh
#
# Usage: scripts/build_rootencoder_from_source.sh [output-dir]
#        (default output: build/rootencoder-maven)
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TAG="2.8.1"
SRC="$ROOT/build/rootencoder-src"
OUT="$(mkdir -p "${1:-$ROOT/build/rootencoder-maven}" && cd "${1:-$ROOT/build/rootencoder-maven}" && pwd)"
require_cmd git "installa git"
require_cmd java "serve un JDK 17"
[[ -n "${ANDROID_HOME:-}${ANDROID_SDK_ROOT:-}" ]] || die "ANDROID_HOME non impostato: serve l'Android SDK"

if [[ ! -d "$SRC/.git" ]]; then
  git clone --quiet --depth 1 --branch "$TAG" https://github.com/pedroSG94/RootEncoder.git "$SRC"
fi
[[ "$(git -C "$SRC" describe --tags)" == "$TAG" ]] || die "$SRC non è RootEncoder $TAG"
echo "sdk.dir=${ANDROID_HOME:-$ANDROID_SDK_ROOT}" >"$SRC/local.properties"

# Only the modules used by the app (library and its dependencies).
MODULES=(common encoder rtmp rtsp srt udp whip library)
TASKS=()
for module in "${MODULES[@]}"; do TASKS+=(":$module:publishToMavenLocal"); done
info "Compilo e pubblico RootEncoder $TAG in $OUT"
(cd "$SRC" && ./gradlew --no-daemon "-Dmaven.repo.local=$OUT" "${TASKS[@]}")
[[ -d "$OUT/com/github/pedroSG94/library/$TAG" ]] || die "pubblicazione non trovata in $OUT"
info "Fatto. Compila l'app con: ROOTENCODER_MAVEN_REPO=$OUT scripts/build_android.sh"
