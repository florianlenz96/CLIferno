#!/bin/bash
set -euo pipefail
umask 077

# Name stays "Atext …" on purpose: a new certificate would reset macOS permissions.
identity="Atext Local Development"
keychain="$(security default-keychain -d user | sed 's/^[[:space:]]*"//; s/"[[:space:]]*$//')"
if security find-identity -v -p codesigning "$keychain" | grep -F "\"$identity\"" >/dev/null; then
    printf 'Vorhandene Signatur wird weiterverwendet: %s\n' "$identity"
    exit 0
fi

temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/cliferno-signing.XXXXXX")"
cleanup() {
    rm -f "$temp_dir/private-key.pem" "$temp_dir/signing-key.pem" "$temp_dir/certificate.pem"
    rmdir "$temp_dir"
}
trap cleanup EXIT

if security find-certificate -c "$identity" -p "$keychain" >"$temp_dir/certificate.pem" 2>/dev/null; then
    printf 'Vorhandenes Zertifikat „Atext Local Development“ gefunden; Vertrauen für Codesignierung wird eingerichtet.\n'
else
    openssl req -x509 -newkey rsa:2048 -noenc \
        -keyout "$temp_dir/private-key.pem" -out "$temp_dir/certificate.pem" \
        -days 3650 -subj "/CN=$identity/" \
        -addext "basicConstraints=critical,CA:false" \
        -addext "keyUsage=critical,digitalSignature" \
        -addext "extendedKeyUsage=critical,codeSigning" 2>/dev/null
    openssl rsa -in "$temp_dir/private-key.pem" -traditional \
        -out "$temp_dir/signing-key.pem" 2>/dev/null
    security import "$temp_dir/signing-key.pem" -k "$keychain" \
        -t priv -f openssl -x -T /usr/bin/codesign
    security import "$temp_dir/certificate.pem" -k "$keychain" -t cert -f pemseq
fi

# Trust is user-local and limited to codesigning, not TLS or other policies.
security add-trusted-cert -r trustRoot -p codeSign -k "$keychain" "$temp_dir/certificate.pem"
if ! security find-identity -v -p codesigning "$keychain" | grep -F "\"$identity\"" >/dev/null; then
    printf 'Das Zertifikat ist noch nicht als Codesignatur verfügbar. Bitte im Schlüsselbund prüfen.\n' >&2
    exit 1
fi
printf 'Lokale Codesignatur eingerichtet: %s\n' "$identity"
