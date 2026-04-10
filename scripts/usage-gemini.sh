#!/usr/bin/env bash
# usage-gemini.sh - Token usage report for Gemini CLI
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ ! -f "$SCRIPT_DIR/lib/usage-gemini.py" ]; then
    echo "❌ lib/usage-gemini.py not found" >&2; exit 1
fi
exec python3 "$SCRIPT_DIR/lib/usage-gemini.py" "$@"
