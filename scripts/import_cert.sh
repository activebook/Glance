#!/bin/bash
# scripts/import_cert.sh — Imports the repository's stable code-signing certificate into the macOS Keychain.
set -euo pipefail

IDENT="GlanceCodeSign"
P12_PATH="certs/glance_codesign.p12"
P12_PASS="glance-signing-secret"

if [ ! -f "$P12_PATH" ]; then
    echo "Certificate $P12_PATH not found, skipping import."
    exit 0
fi

# In CI environment: create a dedicated keychain, unlock, and configure partition list
if [ -n "${CI:-}" ]; then
    KEYCHAIN_PATH="${RUNNER_TEMP:-/tmp}/build.keychain"
    KEYCHAIN_PASS="glance-ci-keychain"

    echo "Configuring CI Keychain at $KEYCHAIN_PATH..."
    security create-keychain -p "$KEYCHAIN_PASS" "$KEYCHAIN_PATH" || true
    security default-keychain -s "$KEYCHAIN_PATH" || true
    security unlock-keychain -p "$KEYCHAIN_PASS" "$KEYCHAIN_PATH" || true
    security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH" || true

    echo "Importing certificate into CI keychain..."
    security import "$P12_PATH" \
        -k "$KEYCHAIN_PATH" \
        -P "$P12_PASS" \
        -T /usr/bin/codesign \
        -T /usr/bin/security

    security set-key-partition-list -S apple-tool:,apple: -s -k "$KEYCHAIN_PASS" "$KEYCHAIN_PATH" || true
    echo "CI Keychain configured successfully with identity: $IDENT"
    exit 0
fi

# Local development environment: check if already in login keychain
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$IDENT"; then
    echo "Identity '$IDENT' already present in local keychain."
    exit 0
fi

echo "Importing $IDENT into login keychain..."
LOGIN_KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
if [ ! -f "$LOGIN_KEYCHAIN" ]; then
    LOGIN_KEYCHAIN="$HOME/Library/Keychains/login.keychain"
fi

security import "$P12_PATH" \
    -k "$LOGIN_KEYCHAIN" \
    -P "$P12_PASS" \
    -T /usr/bin/codesign

TMP_CERT="$(mktemp /tmp/glance_cert_XXXXXX.pem)"
openssl pkcs12 -in "$P12_PATH" -nokeys -out "$TMP_CERT" -password "pass:$P12_PASS" 2>/dev/null || true
if [ -f "$TMP_CERT" ]; then
    security add-trusted-cert -p codeSign "$TMP_CERT" 2>/dev/null || true
    rm -f "$TMP_CERT"
fi

echo "Imported and trusted $IDENT in local keychain."
