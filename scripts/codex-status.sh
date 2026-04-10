#!/usr/bin/env bash
# codex-status.sh - Check auth, token usage, and configuration for Codex CLI
#
# Usage:
#   codex-status.sh                       # Show full status
#   codex-status.sh --auth                # Show auth status only
#   codex-status.sh --verify              # Verify API key validity
#   codex-status.sh --config               # Show config
#   codex-status.sh --json                # Output as JSON

set -euo pipefail

CODEX_HOME="${CODEX_HOME:-${HOME}/.codex}"
CODEX_CONFIG="${CODEX_HOME}/config.toml"
CODEX_AUTH="${CODEX_HOME}/auth.json"
CODEX_SESSION_DIR="${HOME}/.local/share/codex/sessions"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/lib/common.sh" ]; then
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/lib/common.sh"
else
    _mask_key() { local v="$1" l=${#1}; if [ "$l" -gt 12 ]; then printf '%s' "${v:0:4}****${v: -4}"; elif [ "$l" -gt 0 ]; then printf '%s' "****(masked)"; else printf '%s' "(not set)"; fi; }
fi

usage() {
    cat << 'USAGE'
Codex CLI — Status & Usage Checker

Usage: codex-status.sh [options]

Options:
  --auth                Show auth status only
  --verify              Verify API key validity
  --config              Show configuration
  --json                Output as JSON
  --help, -h            Show this help
USAGE
    exit 0
}

check_auth() {
    echo "Authentication Status:"
    echo ""

    if [ -f "$CODEX_AUTH" ]; then
        local auth_size
        auth_size=$(wc -c < "$CODEX_AUTH" | tr -d ' ')
        echo "  Auth file: $CODEX_AUTH ($auth_size bytes)"

        local auth_type
        auth_type=$(python3 -c "
import json, sys
try:
    data = json.load(open(sys.argv[1]))
    if 'access_token' in data:
        print('token')
    elif 'api_key' in data:
        print('api_key')
    elif 'type' in data:
        print(data['type'])
    else:
        print('unknown')
except:
    print('error')
" "$CODEX_AUTH" 2>/dev/null || echo "unknown")

        case "$auth_type" in
            token) echo "  ✅ Auth type: ChatGPT token" ;;
            api_key) echo "  ✅ Auth type: API key" ;;
            oauth) echo "  ✅ Auth type: OAuth" ;;
            *) echo "  ⚠️  Auth type: $auth_type" ;;
        esac

        local expires
        expires=$(python3 -c "
import json, sys
try:
    data = json.load(open(sys.argv[1]))
    exp = data.get('expires_at', data.get('expires', 0))
    if exp:
        from datetime import datetime
        dt = datetime.fromtimestamp(exp)
        print(dt.strftime('%Y-%m-%d %H:%M'))
    else:
        print('never')
except:
    print('unknown')
" "$CODEX_AUTH" 2>/dev/null || echo "unknown")

        if [ "$expires" != "never" ] && [ "$expires" != "unknown" ]; then
            echo "  Expires: $expires"
        fi
    else
        echo "  ⚠️  No auth file found at $CODEX_AUTH"
    fi

    echo ""
    echo "  Environment:"
    if [ -n "${OPENAI_API_KEY:-}" ]; then
        echo "  OPENAI_API_KEY: $(_mask_key "$OPENAI_API_KEY")"
    else
        echo "  OPENAI_API_KEY: (not set)"
    fi

    if command -v codex &>/dev/null; then
        local version
        version=$(codex --version 2>&1 | head -1 || echo "unknown")
        echo "  CLI version: $version"
    else
        echo "  CLI: not installed"
    fi
}

verify_key() {
    echo "Verifying credentials..."
    echo ""

    if [ -n "${OPENAI_API_KEY:-}" ]; then
        echo "  Testing OPENAI_API_KEY..."
        local response
        response=$(curl -s -w "\n%{http_code}" \
            -H "Authorization: Bearer $OPENAI_API_KEY" \
            "https://api.openai.com/v1/models" 2>/dev/null) || {
            echo "  ❌ Failed to connect to OpenAI API."
            return
        }
        local http_code
        http_code=$(echo "$response" | tail -1)
        case "$http_code" in
            200)
                echo "  ✅ API key valid."
                local model_count
                model_count=$(echo "$response" | sed '$d' | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d.get('data',[])))" 2>/dev/null || echo "unknown")
                echo "  Available models: $model_count"
                ;;
            401) echo "  ❌ Invalid API key." ;;
            429) echo "  ⚠ Rate limited." ;;
            *) echo "  ❌ Unexpected response (HTTP $http_code)." ;;
        esac
        echo "  Usage dashboard: https://platform.openai.com/usage"
    elif [ -f "$CODEX_AUTH" ]; then
        echo "  ℹ Using ChatGPT OAuth - no verification needed."
        echo "  ChatGPT subscription includes Codex usage."
    else
        echo "  ❌ No credentials found."
        echo "  Run 'codex login' to authenticate."
    fi
}

show_config() {
    echo "Configuration:"
    echo ""

    if [ -f "$CODEX_CONFIG" ]; then
        echo "  Config file: $CODEX_CONFIG"

        local model
        model=$(grep -E '^model\s*=' "$CODEX_CONFIG" 2>/dev/null | head -1 | cut -d'=' -f2- | tr -d ' "' || echo "default")
        echo "  Model: ${model:-default}"

        local provider
        provider=$(grep -E '^\[\[model_providers\]\]' -A 10 "$CODEX_CONFIG" 2>/dev/null | grep '^name\s*=' | head -1 | cut -d'=' -f2- | tr -d ' "' || echo "openai (default)")
        echo "  Provider: ${provider:-openai}"

        local sandbox
        sandbox=$(grep -E '^sandbox_mode\s*=' "$CODEX_CONFIG" 2>/dev/null | cut -d'=' -f2- | tr -d ' "' || echo "read-only")
        echo "  Sandbox: ${sandbox:-read-only}"
    else
        echo "  ⚠️  Config file not found at $CODEX_CONFIG"
        echo "  Running 'codex' will create default config."
    fi
}

output_json() {
    python3 -c "
import json, os, sys

codex_auth = sys.argv[1]
codex_config = sys.argv[2]

result = {
    'home': os.environ.get('CODEX_HOME', '$CODEX_HOME'),
    'config_file': codex_config,
    'auth_file': codex_auth,
    'auth_mode': 'unknown'
}

# Check auth mode
if os.path.exists(codex_auth):
    result['auth_file_exists'] = True
    try:
        data = json.load(open(codex_auth))
        if 'access_token' in data:
            result['auth_mode'] = 'chatgpt_token'
        elif 'api_key' in data:
            result['auth_mode'] = 'api_key'
        elif data.get('type') == 'oauth':
            result['auth_mode'] = 'oauth'
    except:
        pass
else:
    result['auth_file_exists'] = False

# Check env vars
if os.environ.get('OPENAI_API_KEY'):
    result['has_openai_key'] = True
else:
    result['has_openai_key'] = False

# Check config
if os.path.exists(codex_config):
    result['config_exists'] = True
    try:
        import toml
        cfg = toml.load(open(codex_config))
        result['model'] = cfg.get('model', 'default')
        result['sandbox_mode'] = cfg.get('sandbox_mode', 'read-only')
    except:
        pass
else:
    result['config_exists'] = False

print(json.dumps(result, indent=2))
" "$CODEX_AUTH" "$CODEX_CONFIG" 2>/dev/null || echo '{"error": "Unable to generate JSON"}'
}

show_full_status() {
    echo "═══════════════════════════════════════════════════"
    echo "  Codex CLI — Status Report"
    echo "═══════════════════════════════════════════════════"
    echo ""

    check_auth
    echo ""
    show_config
    echo ""
    verify_key
    echo ""

    echo "  Rate Limits:"
    echo "  ┌──────────────────────────────────────────────────┐"
    echo "  │  ChatGPT Plan:  Included with subscription         │"
    echo "  │  API Key:       Varies by tier                    │"
    echo "  └──────────────────────────────────────────────────┘"
    echo ""
    echo "  Docs: https://docs.anthropic.com"
}

ACTION=""

while [ $# -gt 0 ]; do
    case "$1" in
        --auth) ACTION="auth"; shift ;;
        --verify) ACTION="verify"; shift ;;
        --config) ACTION="config"; shift ;;
        --json) ACTION="json"; shift ;;
        --help|-h) usage ;;
        -*) echo "❌ Unknown option: $1"; usage ;;
        *) shift ;;
    esac
done

case "${ACTION:-full}" in
    auth) check_auth ;;
    verify) verify_key ;;
    config) show_config ;;
    json) output_json ;;
    full) show_full_status ;;
esac
