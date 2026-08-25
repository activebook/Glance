#!/usr/bin/env bash
# Builds (debug) and launches Glance.app for local development.
set -euo pipefail
cd "$(dirname "$0")/.."

scripts/make_app.sh debug
open build/Glance.app
