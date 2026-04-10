#!/usr/bin/env bash
# clear-sessions.sh - Clear session data for AI CLI tools
#
# Supports: kilo, opencode, qwen, gemini, claude (or "all")
# Time ranges: today, week, month, 6months, all
#
# Time range semantics: "Delete sessions OLDER than X"
#   today     — Delete yesterday's and older sessions (keep today)
#   week      — Delete sessions older than 7 days (keep last week)
#   month     — Delete sessions older than 30 days (keep last month)
#   6months   — Delete sessions older than 6 months
#   all       — Delete ALL sessions
#
# Usage:
#   clear-sessions.sh --list                          # Show available tools and ranges
#   clear-sessions.sh --tool kilo --range today       # Clear old kilo sessions
#   clear-sessions.sh --tool all --range week         # Clear old sessions for all tools
#   clear-sessions.sh --tool gemini --range month     # Clear old gemini sessions
#   clear-sessions.sh --tool kilo,gemini --range all  # Clear all sessions for specific tools
#   clear-sessions.sh --tool kilo --range week --dry-run  # Preview only
#
# Shortcuts (positional args):
#   clear-sessions.sh kilo today          # Same as --tool kilo --range today
#   clear-sessions.sh all week --dry-run  # Same as --tool all --range week --dry-run
#   clear-sessions.sh all all             # Delete ALL sessions for ALL tools

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ ! -f "$SCRIPT_DIR/lib/clear-sessions.py" ]; then
    echo "Error: lib/clear-sessions.py not found" >&2
    exit 1
fi

exec python3 "$SCRIPT_DIR/lib/clear-sessions.py" "$@"
