#!/usr/bin/env bash
# usage-qwen.sh - Token usage report for Qwen Code CLI
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ ! -f "$SCRIPT_DIR/lib/usage-qwen.py" ]; then
    echo "❌ lib/usage-qwen.py not found" >&2; exit 1
fi
exec python3 "$SCRIPT_DIR/lib/usage-qwen.py" "$@"
