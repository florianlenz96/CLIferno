#!/bin/bash
# Downloads the newest CLIferno build from the GitHub release "latest", signs it with the
# local signing identity (so macOS keeps the permissions) and installs it.
#
#   bash scripts/install.sh            # from the repo
#   bash install.sh --tag latest       # different release tag
#   bash install.sh --dir ~/Applications
set -euo pipefail
umask 022

repo="${CLIFERNO_REPO:-florianlenz96/CLIferno}"
tag="latest"
install_dir="/Applications"
identity="${CLIFERNO_SIGNING_IDENTITY:-Atext Local Development}"
# Certificate name and bundle id keep the former name "Atext" on purpose, so macOS does not
# reset the permissions (Accessibility, Input Monitoring).
bundle_id="dev.local.atext"
# A running copy under the former name is detected as well.
process_pattern='CLIferno|Atext'

while [[ $# -gt 0 ]]; do
    case "$1" in
        --tag) tag="$2"; shift 2 ;;
        --dir) install_dir="$2"; shift 2 ;;
        -h|--help) sed -n '2,8p' "$0"; exit 0 ;;
        *) printf 'Unknown option: %s\n' "$1" >&2; exit 2 ;;
    esac
done

[[ "$(uname)" == "Darwin" ]] || { printf 'CLIferno only runs on macOS.\n' >&2; exit 1; }

work="$(mktemp -d "${TMPDIR:-/tmp}/cliferno-install.XXXXXX")"
trap 'rm -rf "$work"' EXIT

download() { # $1 = asset name
    if command -v gh >/dev/null && gh auth status >/dev/null 2>&1; then
        gh release download "$tag" --repo "$repo" --pattern "$1" --dir "$work" --clobber
    else
        curl -fsSL -o "$work/$1" "https://github.com/$repo/releases/download/$tag/$1"
    fi
}

printf '→ Downloading %s (%s) …\n' "$repo" "$tag"
if ! download CLIferno.zip || ! download CLIferno.zip.sha256; then
    printf 'Download failed. For a private repo, run this first: gh auth login\n' >&2
    exit 1
fi
expected="$(tr -d '[:space:]' < "$work/CLIferno.zip.sha256")"
actual="$(shasum -a 256 "$work/CLIferno.zip" | awk '{print $1}')"
[[ "$expected" == "$actual" ]] || { printf 'Checksum mismatch.\n' >&2; exit 1; }

ditto -x -k "$work/CLIferno.zip" "$work/unpacked"
app="$work/unpacked/CLIferno.app"
[[ -d "$app" ]] || { printf 'CLIferno.app is missing from the archive.\n' >&2; exit 1; }
xattr -dr com.apple.quarantine "$app" 2>/dev/null || true

# Stable local signature: Accessibility/Input Monitoring permissions survive updates.
if ! security find-identity -v -p codesigning | grep -F "\"$identity\"" >/dev/null; then
    printf '→ Local code signing identity missing, setting it up once …\n'
    script_dir="$(cd "$(dirname "$0")" && pwd)"
    if [[ -f "$script_dir/setup-signing.sh" ]]; then
        bash "$script_dir/setup-signing.sh"
    else
        download setup-signing.sh
        bash "$work/setup-signing.sh"
    fi
fi
codesign --force --options runtime --sign "$identity" --identifier "$bundle_id" "$app"
codesign --verify --deep --strict "$app"
# Capture first: with pipefail, `codesign | grep -q` fails via SIGPIPE once grep exits early.
signature_info="$(codesign --display --verbose=2 "$app" 2>&1)"
if ! grep -q 'flags=.*runtime' <<<"$signature_info"; then
    printf 'Hardened Runtime is not enabled. Aborting.\n' >&2
    exit 1
fi

if pgrep -x "$process_pattern" >/dev/null; then
    # Quit gracefully only: CLIferno asks about unsaved changes and restores the clipboard.
    # If quitting is declined, the update aborts.
    printf '→ Quitting running CLIferno …\n'
    osascript -e "tell application id \"$bundle_id\" to quit" >/dev/null 2>&1 || true
    for _ in {1..60}; do pgrep -x "$process_pattern" >/dev/null || break; sleep 0.5; done
    if pgrep -x "$process_pattern" >/dev/null; then
        printf 'CLIferno is still running (quit cancelled?). Please save your changes, quit CLIferno and run this again.\n' >&2
        exit 1
    fi
fi

if ! mkdir -p "$install_dir" 2>/dev/null || [[ ! -w "$install_dir" ]]; then
    printf 'No write access to %s, installing to ~/Applications.\n' "$install_dir"
    install_dir="$HOME/Applications"
    mkdir -p "$install_dir"
fi
target="$install_dir/CLIferno.app"
staged="$install_dir/.CLIferno.app.new"
rm -rf "$staged"
ditto "$app" "$staged"
rm -rf "$target"
mv "$staged" "$target"

# Remove an old install under the former name (same bundle id, otherwise it shows up twice).
for legacy in "$install_dir/Atext.app" "/Applications/Atext.app" "$HOME/Applications/Atext.app"; do
    if [[ -d "$legacy" ]]; then
        if rm -rf "$legacy" 2>/dev/null; then
            printf '→ Removed old version: %s\n' "$legacy"
        else
            printf 'Note: could not remove old version: %s\n' "$legacy"
        fi
    fi
done

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$target/Contents/Info.plist")"
build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$target/Contents/Info.plist")"
printf '✓ CLIferno %s (build %s) installed: %s\n' "$version" "$build" "$target"
open "$target"
