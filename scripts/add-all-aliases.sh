#!/usr/bin/env bash
#
# add-all-aliases.sh - Installs aliases for all AI coding CLI tools
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Installing aliases for all AI coding CLI tools:"
echo "  - Qwen Code"
echo "  - Claude Code"
echo "  - Kilo AI"
echo "  - OpenCode"
echo "  - Gemini Code"
echo ""

# Install all aliases
"${SCRIPT_DIR}/qwen/add-qwen-aliases.sh"
"${SCRIPT_DIR}/claude/add-claude-aliases.sh"
"${SCRIPT_DIR}/kilo/add-kilo-aliases.sh"
"${SCRIPT_DIR}/opencode/add-opencode-aliases.sh"
"${SCRIPT_DIR}/gemini/add-gemini-aliases.sh"

echo ""
echo "✅ All aliases installed to ~/.zshrc"
echo ""
echo "To use immediately, run:"
echo "  source ~/.zshrc"
echo ""
echo "Quick reference:"
echo "  qe  / qp   = Qwen"
echo "  ce  / cp   = Claude"
echo "  ke  / kp   = Kilo"
echo "  oe  / op   = OpenCode"
echo "  ge  / gp   = Gemini"
