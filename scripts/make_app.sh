#!/usr/bin/env bash
# Builds Glance and assembles a runnable Glance.app bundle.
#
# Usage:
#   scripts/make_app.sh [release|debug]   (default: release)
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"

# Universal 2 Binary: Build for both Apple Silicon (arm64) and Intel (x86_64)
ARCH_FLAGS=("--arch" "arm64" "--arch" "x86_64")

# --disable-sandbox: some managed/agent environments forbid nested sandbox-exec;
# on a normal Mac this only skips SwiftPM's manifest-compile sandbox (harmless).
echo "Building Universal binary (arm64 + x86_64) [$CONFIG]..."
swift build -c "$CONFIG" "${ARCH_FLAGS[@]}" --disable-sandbox
BIN_PATH="$(swift build -c "$CONFIG" "${ARCH_FLAGS[@]}" --show-bin-path)"

APP_DIR="build/Glance.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BIN_PATH/Glance" "$APP_DIR/Contents/MacOS/Glance"

if [ ! -f "AppIcon.icns" ]; then
    swift scripts/generate_icon.swift
    iconutil -c icns AppIcon.iconset -o AppIcon.icns
    rm -rf AppIcon.iconset
fi

if [ -f "AppIcon.icns" ]; then
    cp "AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
fi

cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Glance</string>
    <key>CFBundleDisplayName</key>
    <string>Glance</string>
    <key>CFBundleIdentifier</key>
    <string>com.activebook.glance</string>
    <key>CFBundleExecutable</key>
    <string>Glance</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <false/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

# Signing: prefer the stable GlanceDev identity so TCC grants (Screen Recording,
# etc.) survive rebuilds. Ad-hoc changes the cdhash every build and silently
# invalidates permissions. Run scripts/make_cert.sh once to create it.
SIGN_IDENTITY="${SIGN_IDENTITY:-GlanceDev}"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$SIGN_IDENTITY"; then
    codesign --force --sign "$SIGN_IDENTITY" "$APP_DIR"
    echo "Signed with stable identity: $SIGN_IDENTITY"
else
    codesign --force --sign - "$APP_DIR"
    echo "Signed ad-hoc (run scripts/make_cert.sh for a stable identity that survives rebuilds)"
fi

echo "Built $APP_DIR"
