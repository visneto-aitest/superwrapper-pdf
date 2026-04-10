#!/usr/bin/env bash
# usage-ollama.sh - Token usage report for Ollama
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ ! -f "$SCRIPT_DIR/lib/usage-ollama.py" ]; then
    echo "Error: lib/usage-ollama.py not found" >&2; exit 1
fi
exec python3 "$SCRIPT_DIR/lib/usage-ollama.py" "$@"
