#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# CLIFERNO_SIGNING_IDENTITY=- signs ad hoc (used by CI; the installer re-signs locally).
# Certificate name and bundle id keep the former name "Atext" on purpose: changing them
# would make macOS revoke the Accessibility and Input Monitoring permissions.
identity="${CLIFERNO_SIGNING_IDENTITY:-Atext Local Development}"
if [[ "$identity" != "-" ]] && ! security find-identity -v -p codesigning | grep -F "\"$identity\"" >/dev/null; then
    printf 'Code signing identity missing: %s\nRun once: bash scripts/setup-signing.sh\n' "$identity" >&2
    exit 1
fi

swift build -c release
bin_path="$(swift build -c release --show-bin-path)"
app_path="$PWD/dist/CLIferno.app"
rm -rf "$app_path"
mkdir -p "$app_path/Contents/MacOS"
cp "$bin_path/CLIferno" "$app_path/Contents/MacOS/CLIferno"
cp Resources/Info.plist "$app_path/Contents/Info.plist"
# Localizations (English is the development language, German is a translation).
mkdir -p "$app_path/Contents/Resources"
for strings in Resources/*.lproj/*.strings; do plutil -lint -s "$strings"; done
cp -R Resources/*.lproj "$app_path/Contents/Resources/"
if [[ -n "${CLIFERNO_BUILD_VERSION:-}" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $CLIFERNO_BUILD_VERSION" "$app_path/Contents/Info.plist"
fi
# Hardened Runtime: blocks DYLD_INSERT_LIBRARIES injection into the Accessibility-trusted process.
codesign --force --options runtime --sign "$identity" --identifier dev.local.atext "$app_path"
codesign --verify --deep --strict "$app_path"
# Capture first: with pipefail, `codesign | grep -q` fails via SIGPIPE once grep exits early.
signature_info="$(codesign --display --verbose=2 "$app_path" 2>&1)"
if ! grep -q 'flags=.*runtime' <<<"$signature_info"; then
    printf 'Hardened Runtime is not enabled. Aborting.\n' >&2
    exit 1
fi
printf '\nApp built: %s\nLaunch: open "%s"\n' "$app_path" "$app_path"
