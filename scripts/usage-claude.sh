#!/usr/bin/env bash
# usage-claude.sh - Token usage report for Claude Code CLI
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ ! -f "$SCRIPT_DIR/lib/usage-claude.py" ]; then
    echo "❌ lib/usage-claude.py not found" >&2; exit 1
fi
exec python3 "$SCRIPT_DIR/lib/usage-claude.py" "$@"
