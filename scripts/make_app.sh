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

# Stamp target SDK 26.0 into Mach-O LC_BUILD_VERSION load command so macOS Tahoe
# enables modern Liquid Glass floating sidebar styling without falling into compatibility mode.
if command -v vtool >/dev/null 2>&1; then
    echo "Stamping target SDK 26.0 via vtool..."
    vtool -set-build-version macos 14.0 26.0 -replace \
          -output "$APP_DIR/Contents/MacOS/Glance" "$APP_DIR/Contents/MacOS/Glance" 2>/dev/null || true
fi

if [ ! -f "AppIcon.icns" ]; then
    swift scripts/generate_icon.swift
    iconutil -c icns AppIcon.iconset -o AppIcon.icns
    rm -rf AppIcon.iconset
fi

if [ -f "AppIcon.icns" ]; then
    cp "AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
fi

# Version Resolution: prioritize $VERSION env var, fallback to latest git tag, or default to 0.1.0
GIT_TAG="$(git describe --tags --abbrev=0 2>/dev/null || echo "")"
RAW_VERSION="${VERSION:-${GIT_TAG:-0.1.0}}"
APP_VERSION="${RAW_VERSION#v}" # Strip leading 'v' if present (e.g. v0.1.0 -> 0.1.0)
APP_BUILD="${BUILD_NUM:-$(git rev-list --count HEAD 2>/dev/null || echo "1")}"

echo "Packaging Glance.app (Version: $APP_VERSION, Build: $APP_BUILD)..."

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
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
    <string>${APP_VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${APP_BUILD}</string>
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
# invalidates permissions.
SIGN_IDENTITY="${SIGN_IDENTITY:-GlanceDev}"
if [ -z "${CI:-}" ]; then
    if ! security find-identity -v -p codesigning 2>/dev/null | grep -q "$SIGN_IDENTITY"; then
        if [ -f "scripts/make_cert.sh" ]; then
            echo "Creating stable self-signed identity '$SIGN_IDENTITY'..."
            bash scripts/make_cert.sh || true
        fi
    fi
fi

if security find-identity -v -p codesigning 2>/dev/null | grep -q "$SIGN_IDENTITY"; then
    if codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_DIR" 2>/dev/null; then
        echo "Signed with stable identity: $SIGN_IDENTITY"
    else
        codesign --force --deep --sign - "$APP_DIR"
        echo "Signed ad-hoc (fallback)"
    fi
else
    codesign --force --deep --sign - "$APP_DIR"
    echo "Signed ad-hoc"
fi

echo "Built $APP_DIR"
