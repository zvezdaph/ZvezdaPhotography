#!/usr/bin/env bash
# Verifies the native Kotlin sources of the Android app WITHOUT the Android SDK
# (useful where dl.google.com / jitpack.io are not reachable):
#   1. compiles them, together with the RootEncoder 2.8.1 sources, against
#      Robolectric's android-all (Android 16, API 36) and the Flutter engine jar;
#   2. checks that the bytecode references only PUBLIC Android 16 SDK APIs and
#      that every API newer than minSdk 26 is a reviewed, version-guarded call
#      (tools/android-compile-check/min_sdk_baseline.txt).
# The real APK build (scripts/build_android.sh) remains the reference: this
# check does not process resources, the manifest, D8 or packaging.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

ROOTENCODER_TAG="2.8.1"
AOSP_API_BRANCH="lineage-23.0" # LineageOS mirror of AOSP, Android 16 (API 36)
TOOL="$ROOT/tools/android-compile-check"
OUT="$ROOT/build/android-compile-check"
SRC="$ROOT/build/rootencoder-src"

require_flutter
for cmd in java javap python3 git curl; do require_cmd "$cmd" "necessario per la verifica"; done
# android-all API 36 is compiled for Java 21 (class file version 65): javac 17 cannot read it.
JAVA_BIN="${JAVA_HOME:+$JAVA_HOME/bin/}java"
JAVA_MAJOR="$("$JAVA_BIN" -XshowSettings:properties -version 2>&1 | sed -n 's/^ *java.specification.version = //p')"
[[ "${JAVA_MAJOR%%.*}" =~ ^[0-9]+$ && "${JAVA_MAJOR%%.*}" -ge 21 ]] ||
  die "serve un JDK 21 o superiore per questa verifica (android-all API 36 è compilato per Java 21): trovato ${JAVA_MAJOR:-sconosciuto} in $JAVA_BIN"

if [[ ! -d "$SRC/.git" ]]; then
  info "Scarico i sorgenti di RootEncoder $ROOTENCODER_TAG"
  git clone --quiet --depth 1 --branch "$ROOTENCODER_TAG" https://github.com/pedroSG94/RootEncoder.git "$SRC"
fi
[[ "$(git -C "$SRC" describe --tags)" == "$ROOTENCODER_TAG" ]] || die "$SRC non è RootEncoder $ROOTENCODER_TAG"
python3 "$TOOL/gen_rootencoder_r.py" "$SRC" "$OUT/stubs"

FLUTTER_ROOT_DIR="$(cd "$(dirname "$(readlink -f "$(command -v flutter)")")/.." && pwd)"
FLUTTER_JAR="$FLUTTER_ROOT_DIR/bin/cache/artifacts/engine/android-arm64/flutter.jar"
[[ -f "$FLUTTER_JAR" ]] || flutter precache --android
[[ -f "$FLUTTER_JAR" ]] || die "flutter.jar non trovato in $FLUTTER_JAR"

info "Compilazione Kotlin/Java (app + RootEncoder) contro android-all API 36"
"$ROOT/apps/remote_camera/android/gradlew" -p "$TOOL" --no-daemon --quiet --warning-mode=none \
  "-PflutterJar=$FLUTTER_JAR" "-ProotEncoderSrc=$SRC" "-PgeneratedStubs=$OUT/stubs" classes

mkdir -p "$OUT/api"
declare -A API_FILES=(
  [framework.txt]="android_frameworks_base/$AOSP_API_BRANCH/core/api/current.txt"
  [connectivity.txt]="android_packages_modules_Connectivity/$AOSP_API_BRANCH/framework/api/current.txt"
  [wifi.txt]="android_packages_modules_Wifi/$AOSP_API_BRANCH/framework/api/current.txt"
  [mediaprovider.txt]="android_packages_providers_MediaProvider/$AOSP_API_BRANCH/apex/framework/api/current.txt"
)
for name in "${!API_FILES[@]}"; do
  if [[ ! -s "$OUT/api/$name" ]]; then
    curl -fsSL --retry 3 -o "$OUT/api/$name" "https://raw.githubusercontent.com/LineageOS/${API_FILES[$name]}"
  fi
done
# Public API of Android 8.0 (API 26, the app's minSdk), from the AOSP mirror.
if [[ ! -s "$OUT/api-26.txt" ]]; then
  curl -fsSL --retry 3 -o "$OUT/api-26.txt" \
    "https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/android-8.0.0_r1/api/current.txt"
fi

info "Controllo API: solo SDK pubblico (API 36) e guardie di versione per minSdk 26"
python3 "$TOOL/check_public_api.py" "$TOOL/build/classes/kotlin/main/tv/peoplecare" \
  --min-sdk-api "$OUT/api-26.txt" --baseline "$TOOL/min_sdk_baseline.txt" --classpath "$FLUTTER_JAR" \
  "$OUT"/api/*.txt
info "Sorgenti Kotlin verificati: compilano, usano solo API pubbliche e rispettano minSdk 26"
