#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# ATEXT_SIGNING_IDENTITY=- signs ad hoc (used by CI; the installer re-signs locally).
identity="${ATEXT_SIGNING_IDENTITY:-Atext Local Development}"
if [[ "$identity" != "-" ]] && ! security find-identity -v -p codesigning | grep -F "\"$identity\"" >/dev/null; then
    printf 'Codesignatur fehlt: %s\nEinmalig ausführen: bash scripts/setup-signing.sh\n' "$identity" >&2
    exit 1
fi

swift build -c release
bin_path="$(swift build -c release --show-bin-path)"
app_path="$PWD/dist/Atext.app"
rm -rf "$app_path"
mkdir -p "$app_path/Contents/MacOS"
cp "$bin_path/Atext" "$app_path/Contents/MacOS/Atext"
cp Resources/Info.plist "$app_path/Contents/Info.plist"
if [[ -n "${ATEXT_BUILD_VERSION:-}" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $ATEXT_BUILD_VERSION" "$app_path/Contents/Info.plist"
fi
codesign --force --sign "$identity" --identifier dev.local.atext "$app_path"
codesign --verify --deep --strict "$app_path"
printf '\nApp erstellt: %s\nStarten: open "%s"\n' "$app_path" "$app_path"
