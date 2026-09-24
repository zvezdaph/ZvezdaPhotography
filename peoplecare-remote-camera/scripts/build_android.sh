#!/usr/bin/env bash
# Builds the Android APK of PeopleCare Remote Camera.
#
# Usage: scripts/build_android.sh [debug|release]   (default: debug)
#
# Reads from the environment or from .env:
#   CONTROL_PLANE_URL            default control plane baked into the APK
#   ALLOW_INSECURE_CONTROL_PLANE true only for local http:// tests (debug)
#   ROOTENCODER_MAVEN_REPO       local Maven repo made by build_rootencoder_from_source.sh
#
# Equivalent manual build: cd apps/remote_camera && flutter pub get &&
# cd android && ./gradlew assembleDebug
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

MODE="${1:-debug}"
[[ "$MODE" == "debug" || "$MODE" == "release" ]] || die "modalità non valida: $MODE (debug|release)"
require_flutter

CONTROL_PLANE_URL="$(env_get CONTROL_PLANE_URL)"
ALLOW_INSECURE="$(env_get ALLOW_INSECURE_CONTROL_PLANE false)"
ROOTENCODER_REPO="$(env_get ROOTENCODER_MAVEN_REPO)"

DEFINES=()
if [[ -n "$CONTROL_PLANE_URL" ]]; then
  [[ "$CONTROL_PLANE_URL" =~ ^https:// || "$ALLOW_INSECURE" == "true" ]] ||
    die "CONTROL_PLANE_URL deve iniziare con https:// ($CONTROL_PLANE_URL)"
  DEFINES+=("--dart-define=CONTROL_PLANE_URL=$CONTROL_PLANE_URL")
  info "Regia predefinita: $CONTROL_PLANE_URL"
else
  warn "CONTROL_PLANE_URL non impostato: l'indirizzo della regia andrà inserito nell'app"
fi
if [[ "$ALLOW_INSECURE" == "true" ]]; then
  [[ "$MODE" == "debug" ]] || die "ALLOW_INSECURE_CONTROL_PLANE è consentito solo nelle build debug"
  warn "Build di test: consentita una regia http:// non cifrata"
  DEFINES+=("--dart-define=ALLOW_INSECURE_CONTROL_PLANE=true")
fi
if [[ -n "$ROOTENCODER_REPO" ]]; then
  [[ -d "$ROOTENCODER_REPO" ]] || die "ROOTENCODER_MAVEN_REPO non esiste: $ROOTENCODER_REPO"
  export ORG_GRADLE_PROJECT_rootEncoderMavenRepo="$ROOTENCODER_REPO"
  info "RootEncoder dal repository locale $ROOTENCODER_REPO"
fi

cd "$ROOT/apps/remote_camera"
info "$(flutter --version | head -n 1)"
flutter pub get
info "flutter analyze"
flutter analyze
info "flutter test"
flutter test
info "flutter build apk --$MODE"
flutter build apk "--$MODE" ${DEFINES[@]+"${DEFINES[@]}"}

APK="build/app/outputs/flutter-apk/app-$MODE.apk"
[[ -f "$APK" ]] || die "APK non trovato: $APK"
mkdir -p "$ROOT/dist"
cp "$APK" "$ROOT/dist/peoplecare-remote-camera-$MODE.apk"
info "APK: dist/peoplecare-remote-camera-$MODE.apk ($(du -h "$APK" | cut -f1))"
info "Installazione: adb install -r dist/peoplecare-remote-camera-$MODE.apk"
