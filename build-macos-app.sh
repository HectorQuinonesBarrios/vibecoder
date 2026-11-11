#!/bin/bash
# Build a self-contained app/DMG. The checkout-based wrapper is retained in
# build-macos-launcher.sh. Bundled notices (licenses,
# THIRD_PARTY_PROVENANCE.json and ACKNOWLEDGMENTS.md) are owned by Odysseus.spec.
set -euo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_DIR"
BUILD_PYTHON="${ODYSSEUS_BUILD_PYTHON:-python3}"
if [ -z "${ODYSSEUS_BUILD_PYTHON:-}" ] && [ -x .venv/bin/python ]; then
  BUILD_PYTHON="$REPO_DIR/.venv/bin/python"
fi
exec "$BUILD_PYTHON" scripts/build_macos.py "$@"
