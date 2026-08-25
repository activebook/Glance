#!/usr/bin/env bash
# Builds a production release of Glance.app (Universal binary: arm64 + x86_64)
# and packages it into a distribution-ready archive in build/.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> Building Glance.app in release mode..."
scripts/make_app.sh release

echo "==> Packaging release archive..."
cd build
rm -f Glance.zip
zip -r -y -q Glance.zip Glance.app
cd ..

echo "==> Release build complete:"
echo "    App Bundle: build/Glance.app"
echo "    Archive:    build/Glance.zip"
