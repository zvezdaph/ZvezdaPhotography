#!/usr/bin/env bash
# Controlli di qualità: formattazione, analisi statica e test.
# Sono gli stessi controlli eseguiti dalla pipeline CI.
set -euo pipefail
cd "$(dirname "$0")/.."

step() { printf '\n==> %s\n' "$1"; }

step 'flutter pub get'
flutter pub get

step 'dart format (verifica)'
dart format --output=none --set-exit-if-changed lib test

step 'flutter analyze'
flutter analyze

step 'flutter test'
flutter test

printf '\nTutti i controlli sono stati superati.\n'
