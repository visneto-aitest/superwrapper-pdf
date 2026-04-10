#!/usr/bin/env bash
# usage-kilo.sh - Token usage report for Kilo CLI
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ ! -f "$SCRIPT_DIR/lib/usage-kilo.py" ]; then
    echo "❌ lib/usage-kilo.py not found" >&2; exit 1
fi

exec python3 "$SCRIPT_DIR/lib/usage-kilo.py" "$@"
