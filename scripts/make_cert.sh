#!/usr/bin/env bash
# Creates the stable "GlanceDev" self-signed code-signing certificate (one-time).
# Idempotent: exits early if the identity already exists.
set -euo pipefail

IDENT="GlanceDev"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

# Already present? Nothing to do.
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$IDENT"; then
    echo "Identity '$IDENT' already exists — nothing to do."
    exit 0
fi

echo "Generating self-signed code-signing certificate '$IDENT' (10 years)…"
openssl req -newkey rsa:2048 -nodes \
    -keyout "$WORKDIR/key.pem" \
    -x509 -days 3650 \
    -out "$WORKDIR/cert.pem" \
    -subj "/CN=$IDENT" \
    -addext "keyUsage=digitalSignature" \
    -addext "extendedKeyUsage=codeSigning"

echo "Exporting PKCS#12 (legacy ciphers — macOS keychain import can't read OpenSSL 3 defaults)…"
openssl pkcs12 -export \
    -out "$WORKDIR/$IDENT.p12" \
    -inkey "$WORKDIR/key.pem" \
    -in "$WORKDIR/cert.pem" \
    -password pass:glance-dev-import \
    -keypbe PBE-SHA1-3DES \
    -certpbe PBE-SHA1-3DES \
    -macalg sha1

echo "Importing into login keychain (pre-authorizing /usr/bin/codesign)…"
security import "$WORKDIR/$IDENT.p12" \
    -k "$HOME/Library/Keychains/login.keychain-db" \
    -P glance-dev-import \
    -T /usr/bin/codesign

echo "Trusting certificate for code signing (user trust domain, no sudo)…"
security add-trusted-cert -p codeSign "$WORKDIR/cert.pem"

echo
echo "Result:"
security find-identity -v -p codesigning | grep "$IDENT" && echo "OK: identity ready." || {
    echo "WARNING: identity not listed as valid yet. If a GUI prompt appeared, click Allow and re-run this script." >&2
    exit 1
}
