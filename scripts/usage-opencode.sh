#!/usr/bin/env bash
# usage-opencode.sh - Token usage report for OpenCode CLI
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ ! -f "$SCRIPT_DIR/lib/usage-opencode.py" ]; then
    echo "❌ lib/usage-opencode.py not found" >&2; exit 1
fi
exec python3 "$SCRIPT_DIR/lib/usage-opencode.py" "$@"
