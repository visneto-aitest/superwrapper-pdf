#!/usr/bin/env bash
# claude-switch.sh - Claude CLI Provider Switcher
#
# Configures Claude Code to use different API providers.
# Must be sourced: source claude-switch.sh [provider]
#
# Usage:
#   source claude-switch.sh openrouter      # Use OpenRouter
#   source claude-switch.sh kilo            # Use Kilo.ai
#   source claude-switch.sh omni            # Use OmniRoute (local proxy)
#   source claude-switch.sh opencode         # Use OpenCode
#   source claude-switch.sh reset           # Reset to Anthropic default
#
# Required env vars:
#   OPENROUTER_API_KEY, KILO_API_KEY, OPENCODE_API_KEY, OMNIROUTE_API_KEY

PROVIDER="${1:-}"

if [ -z "$PROVIDER" ]; then
    echo "Claude CLI Provider Switcher"
    echo ""
    echo "Usage: source claude-switch.sh [provider]"
    echo ""
    echo "Providers:"
    echo "  openrouter  - Use OpenRouter AI (requires OPENROUTER_API_KEY)"
    echo "  kilo      - Use Kilo.ai (requires KILO_API_KEY)"
    echo "  omni      - Use OmniRoute local proxy (requires OMNIROUTE_API_KEY)"
    echo "  opencode  - Use OpenCode (requires OPENCODE_API_KEY)"
    echo "  reset     - Reset to Anthropic default"
    echo ""
    echo "Default models (free):"
    echo "  openrouter: anthropic/claude-3-haiku-20240307"
    echo "  kilo: claude-sonnet-4-20250514"
    echo "  opencode: claude-sonnet-4-20250514"
    echo ""
    echo "Override model with env vars:"
    echo "  OPENROUTER_MODEL, KILO_MODEL, OPENCODE_MODEL"
    echo ""
    echo "Required environment variables:"
    echo "  OPENROUTER_API_KEY, KILO_API_KEY, OPENCODE_API_KEY, OMNIROUTE_API_KEY"
    return 0
fi

reset_claude_vars() {
    unset ANTHROPIC_BASE_URL 2>/dev/null || true
    unset ANTHROPIC_AUTH_TOKEN 2>/dev/null || true
    unset ANTHROPIC_API_KEY 2>/dev/null || true
    unset CLAUDE_MODEL 2>/dev/null || true
}

case "$PROVIDER" in
    openrouter)
        if [ -z "${OPENROUTER_API_KEY:-}" ]; then
            echo "Error: OPENROUTER_API_KEY is not set."
            return 1
        fi
        reset_claude_vars
        export ANTHROPIC_BASE_URL="https://openrouter.ai/api"
        export ANTHROPIC_AUTH_TOKEN="$OPENROUTER_API_KEY"
        export ANTHROPIC_API_KEY=""
        export CLAUDE_MODEL="${OPENROUTER_MODEL:-anthropic/claude-3-haiku-20240307}"
        echo "✓ Configured for OpenRouter"
        echo "  Base URL: $ANTHROPIC_BASE_URL"
        echo "  Model: $CLAUDE_MODEL (free)"
        ;;

    kilo)
        if [ -z "${KILO_API_KEY:-}" ]; then
            echo "Error: KILO_API_KEY is not set."
            return 1
        fi
        reset_claude_vars
        export ANTHROPIC_BASE_URL="https://api.kilo.ai/v1"
        export ANTHROPIC_AUTH_TOKEN="$KILO_API_KEY"
        export ANTHROPIC_API_KEY=""
        export ANTHROPIC_MODEL="${KILO_MODEL:-claude-sonnet-4-20250514}"
        echo "✓ Configured for Kilo.ai"
        echo "  Base URL: $ANTHROPIC_BASE_URL"
        echo "  Model: $ANTHROPIC_MODEL"
        ;;

    omni|omniroute)
        TOKEN="${OMNIROUTE_API_KEY:-omni-default-token}"
        reset_claude_vars
        export ANTHROPIC_BASE_URL="http://localhost:20128/v1"
        export ANTHROPIC_AUTH_TOKEN="$TOKEN"
        export ANTHROPIC_API_KEY=""
        export ANTHROPIC_MODEL="${OMNI_MODEL:-claude-sonnet-4-20250514}"
        echo "✓ Configured for OmniRoute"
        echo "  Base URL: $ANTHROPIC_BASE_URL"
        echo "  Model: $ANTHROPIC_MODEL"
        ;;

    opencode|orpi)
        if [ -z "${OPENCODE_API_KEY:-}" ]; then
            echo "Error: OPENCODE_API_KEY is not set."
            return 1
        fi
        reset_claude_vars
        export ANTHROPIC_BASE_URL="https://api.opencode.ai/v1"
        export ANTHROPIC_AUTH_TOKEN="$OPENCODE_API_KEY"
        export ANTHROPIC_API_KEY=""
        export ANTHROPIC_MODEL="${OPENCODE_MODEL:-claude-sonnet-4-20250514}"
        echo "✓ Configured for OpenCode"
        echo "  Base URL: $ANTHROPIC_BASE_URL"
        echo "  Model: $ANTHROPIC_MODEL"
        ;;

    reset)
        reset_claude_vars
        echo "✓ Reset to Anthropic default"
        echo "  All provider variables cleared."
        ;;

    *)
        echo "Error: Unknown provider '$PROVIDER'"
        echo ""
        echo "Valid providers: openrouter, kilo, omni, opencode, reset"
        return 1
        ;;
esac