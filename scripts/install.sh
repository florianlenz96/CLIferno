#!/bin/bash
# Lädt den neuesten CLIferno-Build aus dem GitHub-Release "latest", signiert ihn mit der
# lokalen Signatur (damit macOS die Berechtigungen behält) und installiert ihn.
#
#   bash scripts/install.sh            # aus dem Repo
#   bash install.sh --tag latest       # anderes Release-Tag
#   bash install.sh --dir ~/Applications
set -euo pipefail
umask 022

repo="${CLIFERNO_REPO:-florianlenz96/CLIferno}"
tag="latest"
install_dir="/Applications"
identity="${CLIFERNO_SIGNING_IDENTITY:-Atext Local Development}"
# Zertifikatsname und Bundle-ID behalten bewusst den früheren Namen "Atext", damit macOS
# die Freigaben (Bedienungshilfen, Eingabeüberwachung) nicht zurücksetzt.
bundle_id="dev.local.atext"
# Läuft noch eine Version unter dem früheren Namen, wird auch sie erkannt.
process_pattern='CLIferno|Atext'

while [[ $# -gt 0 ]]; do
    case "$1" in
        --tag) tag="$2"; shift 2 ;;
        --dir) install_dir="$2"; shift 2 ;;
        -h|--help) sed -n '2,8p' "$0"; exit 0 ;;
        *) printf 'Unbekannte Option: %s\n' "$1" >&2; exit 2 ;;
    esac
done

[[ "$(uname)" == "Darwin" ]] || { printf 'CLIferno läuft nur unter macOS.\n' >&2; exit 1; }

work="$(mktemp -d "${TMPDIR:-/tmp}/cliferno-install.XXXXXX")"
trap 'rm -rf "$work"' EXIT

download() { # $1 = Asset-Name
    if command -v gh >/dev/null && gh auth status >/dev/null 2>&1; then
        gh release download "$tag" --repo "$repo" --pattern "$1" --dir "$work" --clobber
    else
        curl -fsSL -o "$work/$1" "https://github.com/$repo/releases/download/$tag/$1"
    fi
}

printf '→ Lade %s (%s) …\n' "$repo" "$tag"
if ! download CLIferno.zip || ! download CLIferno.zip.sha256; then
    printf 'Download fehlgeschlagen. Bei privatem Repo zuerst: gh auth login\n' >&2
    exit 1
fi
expected="$(tr -d '[:space:]' < "$work/CLIferno.zip.sha256")"
actual="$(shasum -a 256 "$work/CLIferno.zip" | awk '{print $1}')"
[[ "$expected" == "$actual" ]] || { printf 'Prüfsumme stimmt nicht.\n' >&2; exit 1; }

ditto -x -k "$work/CLIferno.zip" "$work/unpacked"
app="$work/unpacked/CLIferno.app"
[[ -d "$app" ]] || { printf 'CLIferno.app fehlt im Archiv.\n' >&2; exit 1; }
xattr -dr com.apple.quarantine "$app" 2>/dev/null || true

# Stabile lokale Signatur: Bedienungshilfen/Eingabeüberwachung bleiben nach Updates erhalten.
if ! security find-identity -v -p codesigning | grep -F "\"$identity\"" >/dev/null; then
    printf '→ Lokale Codesignatur fehlt, wird einmalig eingerichtet …\n'
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
    printf 'Hardened Runtime ist nicht aktiv. Abbruch.\n' >&2
    exit 1
fi

if pgrep -x "$process_pattern" >/dev/null; then
    # Nur regulär beenden: CLIferno fragt bei ungespeicherten Änderungen nach und stellt die
    # Zwischenablage wieder her. Wird das Beenden abgelehnt, bricht das Update ab.
    printf '→ Laufendes CLIferno wird beendet …\n'
    osascript -e "tell application id \"$bundle_id\" to quit" >/dev/null 2>&1 || true
    for _ in {1..60}; do pgrep -x "$process_pattern" >/dev/null || break; sleep 0.5; done
    if pgrep -x "$process_pattern" >/dev/null; then
        printf 'CLIferno läuft noch (Beenden abgebrochen?). Bitte Änderungen speichern, CLIferno beenden und erneut ausführen.\n' >&2
        exit 1
    fi
fi

if ! mkdir -p "$install_dir" 2>/dev/null || [[ ! -w "$install_dir" ]]; then
    printf 'Kein Schreibrecht für %s, installiere nach ~/Applications.\n' "$install_dir"
    install_dir="$HOME/Applications"
    mkdir -p "$install_dir"
fi
target="$install_dir/CLIferno.app"
staged="$install_dir/.CLIferno.app.new"
rm -rf "$staged"
ditto "$app" "$staged"
rm -rf "$target"
mv "$staged" "$target"

# Alte Installation unter dem früheren Namen entfernen (gleiche Bundle-ID, sonst doppelt).
for legacy in "$install_dir/Atext.app" "/Applications/Atext.app" "$HOME/Applications/Atext.app"; do
    if [[ -d "$legacy" ]]; then
        if rm -rf "$legacy" 2>/dev/null; then
            printf '→ Alte Version entfernt: %s\n' "$legacy"
        else
            printf 'Hinweis: Alte Version konnte nicht entfernt werden: %s\n' "$legacy"
        fi
    fi
done

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$target/Contents/Info.plist")"
build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$target/Contents/Info.plist")"
printf '✓ CLIferno %s (Build %s) installiert: %s\n' "$version" "$build" "$target"
open "$target"
