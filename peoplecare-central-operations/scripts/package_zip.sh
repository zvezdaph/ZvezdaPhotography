#!/usr/bin/env bash
# Crea lo ZIP del codice sorgente del progetto (senza build, cache e pacchetti),
# pronto da consegnare a un altro sviluppatore.
#   scripts/package_zip.sh [file-di-destinazione.zip]
set -euo pipefail
cd "$(dirname "$0")/.."

name="$(basename "$PWD")"
version="$(sed -n 's/^version:[[:space:]]*\([^+[:space:]]*\).*/\1/p' pubspec.yaml)"
out="${1:-dist/peoplecare-central-operations-${version}-src.zip}"
mkdir -p "$(dirname "$out")"
out="$(cd "$(dirname "$out")" && pwd)/$(basename "$out")"
rm -f "$out"

cd ..
zip -r -q -X "$out" "$name" \
  -x "$name/build/*" \
  -x "$name/dist/*" \
  -x "$name/.dart_tool/*" \
  -x "$name/.idea/*" \
  -x "$name/*.iml" \
  -x "$name/.flutter-plugins" \
  -x "$name/.flutter-plugins-dependencies" \
  -x "$name/windows/flutter/ephemeral/*" \
  -x "*/.DS_Store"

echo "Creato: $out"
