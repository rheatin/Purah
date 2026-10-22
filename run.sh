#!/usr/bin/env bash
# ==============================================================================
# run.sh - Build and restart Purah.app
# ==============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
cd "$REPO_ROOT"

echo "🔄 Restarting Purah..."
pkill -x Purah 2>/dev/null || true
sleep 0.5

./build.sh --open "$@"
