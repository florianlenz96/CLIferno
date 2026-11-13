#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

identity="${ATEXT_SIGNING_IDENTITY:-Atext Local Development}"
if ! security find-identity -v -p codesigning | grep -F "\"$identity\"" >/dev/null; then
    printf 'Codesignatur fehlt: %s\nEinmalig ausführen: bash scripts/setup-signing.sh\n' "$identity" >&2
    exit 1
fi

swift build -c release
bin_path="$(swift build -c release --show-bin-path)"
app_path="$PWD/dist/Atext.app"
mkdir -p "$app_path/Contents/MacOS"
cp "$bin_path/Atext" "$app_path/Contents/MacOS/Atext"
cp Resources/Info.plist "$app_path/Contents/Info.plist"
# Hardened Runtime: blocks DYLD_INSERT_LIBRARIES injection into the Accessibility-trusted process.
codesign --force --options runtime --sign "$identity" --identifier dev.local.atext "$app_path"
codesign --verify --deep --strict "$app_path"
if ! codesign --display --verbose=2 "$app_path" 2>&1 | grep -q 'flags=.*runtime'; then
    printf 'Hardened Runtime ist nicht aktiv. Abbruch.\n' >&2
    exit 1
fi
printf '\nApp erstellt: %s\nStarten: open "%s"\n' "$app_path" "$app_path"
