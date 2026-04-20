#!/usr/bin/env bash
# opencode-status.sh - Check provider auth, token usage, and rate limits for OpenCode CLI
#
# OpenCode has no native usage command. This script:
#   1. Checks all configured provider auth status
#   2. Queries provider APIs to verify credentials
#   3. Parses session logs for token usage
#   4. Displays rate limit information
#
# Usage:
#   opencode-status.sh                       # Show full status
#   opencode-status.sh <account>             # Status using specific account
#   opencode-status.sh --providers           # Show provider auth status only
#   opencode-status.sh --usage               # Show token usage summary
#   opencode-status.sh --sessions            # List recent sessions
#   opencode-status.sh --provider <name>     # Check specific provider
#   opencode-status.sh --rate-limits         # Show rate limit info
#   opencode-status.sh --json                # Output as JSON

set -euo pipefail

OPENCODE_ACCOUNTS_DIR="${OPENCODE_ACCOUNTS_DIR:-${HOME}/.config/opencode/accounts}"
OPENCODE_CONFIG_DIR="${HOME}/.config/opencode"
OPENCODE_GLOBAL_CONFIG="${HOME}/.opencode.json"
OPENCODE_SESSION_DIR="${HOME}/.local/share/opencode/sessions"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/lib/common.sh" ]; then
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/lib/common.sh"
else
    _mask_key() { local v="$1" l=${#1}; if [ "$l" -gt 12 ]; then printf '%s' "${v:0:4}****${v: -4}"; elif [ "$l" -gt 0 ]; then printf '%s' "****(masked)"; else printf '%s' "(not set)"; fi; }
    _validate_json() { local f="$1"; if command -v python3 &>/dev/null; then python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$f" 2>/dev/null || return 1; elif command -v jq &>/dev/null; then jq empty "$f" 2>/dev/null || return 1; fi; return 0; }
    _format_tokens() { local c="$1"; if [ "$c" -ge 1000000 ] 2>/dev/null; then printf '%.1fM' "$(echo "scale=1;$c/1000000" | bc 2>/dev/null || echo "$c")"; elif [ "$c" -ge 1000 ] 2>/dev/null; then printf '%.1fK' "$(echo "scale=1;$c/1000" | bc 2>/dev/null || echo "$c")"; else echo "$c"; fi; }
fi

# ─── Find active config ──────────────────────────────────────────────────────

_find_config() {
    if [ -f "${OPENCODE_CONFIG_DIR}/opencode.json" ]; then
        echo "${OPENCODE_CONFIG_DIR}/opencode.json"
    elif [ -f "${OPENCODE_CONFIG_DIR}/.opencode.json" ]; then
        echo "${OPENCODE_CONFIG_DIR}/.opencode.json"
    elif [ -f "$OPENCODE_GLOBAL_CONFIG" ]; then
        echo "$OPENCODE_GLOBAL_CONFIG"
    else
        echo ""
    fi
}

# ─── Load account credentials ────────────────────────────────────────────────

_load_account() {
    local name="$1"
    local account_file="$OPENCODE_ACCOUNTS_DIR/$name.env"

    if [ ! -f "$account_file" ]; then
        echo "❌ Account '$name' not found at $account_file"
        echo "  Create it with: opencode-env create $name"
        echo "  Or list accounts: opencode-env list"
        return 1
    fi

    set -a
    # shellcheck disable=SC1090
    source "$account_file"
    set +a
    return 0
}

# ─── Usage ────────────────────────────────────────────────────────────────────

usage() {
    cat << 'USAGE'
OpenCode CLI — Status & Usage Checker

Usage: opencode-status.sh [options]
       opencode-status.sh <account-name> [options]

Options:
  <account-name>        Load credentials from this account
  --providers           Show provider auth status only
  --usage               Show token usage summary
  --sessions            List recent sessions with token counts
  --provider <name>     Check specific provider
  --rate-limits         Show rate limit information
  --json                Output full status as JSON
  --help, -h            Show this help

Note: OpenCode has no native usage command.
      Provider credentials are verified by querying each provider's API.
USAGE
    exit 0
}

# ─── Check Provider Auth Status ──────────────────────────────────────────────

check_providers() {
    local config_file="${1:-}"
    local specific="${2:-}"

    if [ -z "$config_file" ]; then
        config_file=$(_find_config)
    fi

    if [ -z "$config_file" ] || [ ! -f "$config_file" ]; then
        echo "⚠ No config file found."
        echo "  Expected: ~/.config/opencode/opencode.json or ~/.opencode.json"
        return 1
    fi

    echo "Provider Status:"
    echo ""

    python3 -c "
import json, os, re, sys

try:
    cfg = json.load(open(sys.argv[1]))
    providers = cfg.get('provider', {})
    disabled = set(cfg.get('disabled_providers', []))
    enabled = cfg.get('enabled_providers', list(providers.keys()))

    specific = sys.argv[2] if len(sys.argv) > 2 else ''
    if specific:
        if specific not in providers:
            print(f'❌ Provider \"{specific}\" not found.')
            print(f'   Available: {\", \".join(providers.keys())}')
            sys.exit(1)
        providers = {specific: providers[specific]}
        enabled = [specific]
        disabled = set()

    model = cfg.get('model', 'not set')
    small = cfg.get('small_model', '')
    print(f'Active model: {model}')
    if small:
        print(f'Small model:  {small}')
    print()

    dashboard_links = {
        'anthropic': 'https://console.anthropic.com/settings/keys',
        'openai': 'https://platform.openai.com/api-keys',
        'gemini': 'https://aistudio.google.com/apikey',
        'openrouter': 'https://openrouter.ai/keys',
        'groq': 'https://console.groq.com/keys',
        'xai': 'https://console.x.ai/',
    }

    for name in sorted(providers.keys()):
        pconf = providers[name]
        opts = pconf.get('options', {})
        key = opts.get('apiKey', '')
        base_url = opts.get('baseURL', '')

        is_enabled = name in enabled and name not in disabled
        status = '✅' if is_enabled else ('❌' if name in disabled else '⏸️')

        if key.startswith('{env:'):
            m = re.match(r'\{env:(\w+)\}', key)
            if m:
                val = os.environ.get(m.group(1), '')
                if val:
                    key_display = f'env:{m.group(1)} = {val[:4]}****{val[-4:]}'
                else:
                    key_display = f'env:{m.group(1)} = (not set) ⚠️'
            else:
                key_display = key
        elif key:
            key_display = f'{key[:4]}****{key[-4:]}'
        else:
            key_display = '(no key — may use CLI auth)'

        print(f'  {status} {name}')
        print(f'      Key: {key_display}')
        if base_url:
            print(f'      URL: {base_url}')

        models = pconf.get('models', {})
        if models:
            model_names = list(models.keys())
            print(f'      Models: {\", \".join(model_names[:5])}')
            if len(model_names) > 5:
                print(f'              ... and {len(model_names)-5} more')

        if name in dashboard_links:
            print(f'      Dashboard: {dashboard_links[name]}')
        print()

except Exception as e:
    print(f'  ❌ Error parsing config: {e}')
    sys.exit(1)
" "$config_file" "$specific" 2>/dev/null
}

# ─── Verify Provider API Key ─────────────────────────────────────────────────

verify_provider() {
    local config_file="$1"
    local provider="$2"

    if [ -z "$config_file" ]; then
        config_file=$(_find_config)
    fi

    if [ -z "$config_file" ] || [ ! -f "$config_file" ]; then
        echo "⚠ No config file found."
        return 1
    fi

    # Extract API key for the provider safely
    local api_key
    api_key=$(python3 -c '
import json, os, re, sys
try:
    cfg = json.load(open(sys.argv[1]))
    pconf = cfg.get("provider", {}).get(sys.argv[2], {})
    opts = pconf.get("options", {})
    key = opts.get("apiKey", "")
    if key.startswith("{env:"):
        m = re.match(r"\{env:(\w+)\}", key)
        if m:
            print(os.environ.get(m.group(1), ""))
    elif key:
        print(key)
except:
    pass
' "$config_file" "$provider" 2>/dev/null)

    if [ -z "$api_key" ]; then
        echo "  ⚠ No API key found for provider '$provider'."
        return 0
    fi

    echo "  Verifying $provider API key..."
    case "$provider" in
        anthropic)
            local response
            response=$(curl -s --connect-timeout 10 --max-time 30 -w "\n%{http_code}" \
                -H "x-api-key: $api_key" \
                -H "anthropic-version: 2023-06-01" \
                -H "Content-Type: application/json" \
                -d '{"model":"claude-sonnet-4-20250514","max_tokens":1,"messages":[{"role":"user","content":"hi"}]}' \
                "https://api.anthropic.com/v1/messages" 2>/dev/null) || {
                echo "  ❌ Failed to connect to Anthropic API."
                return 1
            }
            local http_code
            http_code=$(echo "$response" | tail -1)
            case "$http_code" in
                200) echo "  ✅ API key valid." ;;
                401|403) echo "  ❌ Invalid API key." ;;
                429) echo "  ⚠ Rate limited." ;;
                *) echo "  ❌ Unexpected response (HTTP $http_code)." ;;
            esac
            echo "  Usage dashboard: https://console.anthropic.com/settings/usage"
            ;;
        openai)
            local response
            response=$(curl -s --connect-timeout 10 --max-time 30 -w "\n%{http_code}" \
                -H "Authorization: Bearer $api_key" \
                "https://api.openai.com/v1/models" 2>/dev/null) || {
                echo "  ❌ Failed to connect to OpenAI API."
                return 1
            }
            local http_code
            http_code=$(echo "$response" | tail -1)
            case "$http_code" in
                200) echo "  ✅ API key valid." ;;
                401) echo "  ❌ Invalid API key." ;;
                429) echo "  ⚠ Rate limited." ;;
                *) echo "  ❌ Unexpected response (HTTP $http_code)." ;;
            esac
            echo "  Usage dashboard: https://platform.openai.com/usage"
            ;;
        groq)
            local response
            response=$(curl -s --connect-timeout 10 --max-time 30 -w "\n%{http_code}" \
                -H "Authorization: Bearer $api_key" \
                "https://api.groq.com/openai/v1/models" 2>/dev/null) || {
                echo "  ❌ Failed to connect to Groq API."
                return 1
            }
            local http_code
            http_code=$(echo "$response" | tail -1)
            case "$http_code" in
                200) echo "  ✅ API key valid." ;;
                401) echo "  ❌ Invalid API key." ;;
                *) echo "  ❌ Unexpected response (HTTP $http_code)." ;;
            esac
            echo "  Usage dashboard: https://console.groq.com/"
            ;;
        openrouter)
            local response
            response=$(curl -s --connect-timeout 10 --max-time 30 -w "\n%{http_code}" \
                -H "Authorization: Bearer $api_key" \
                "https://openrouter.ai/api/v1/auth/key" 2>/dev/null) || {
                echo "  ❌ Failed to connect to OpenRouter."
                return 1
            }
            local http_code
            http_code=$(echo "$response" | tail -1)
            case "$http_code" in
                200)
                    echo "  ✅ API key valid."
                    local label
                    label=$(echo "$response" | sed '$d' | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('label','unknown'))" 2>/dev/null || echo "unknown")
                    echo "  Label: $label"
                    ;;
                401) echo "  ❌ Invalid API key." ;;
                *) echo "  ❌ Unexpected response (HTTP $http_code)." ;;
            esac
            echo "  Usage dashboard: https://openrouter.ai/activity"
            ;;
        gemini)
            local response
            response=$(curl -s --connect-timeout 10 --max-time 30 -w "\n%{http_code}" \
                -H "x-goog-api-key: $api_key" \
                "https://generativelanguage.googleapis.com/v1beta/models" 2>/dev/null) || {
                echo "  ❌ Failed to connect to Google AI Studio."
                return 1
            }
            local http_code
            http_code=$(echo "$response" | tail -1)
            case "$http_code" in
                200) echo "  ✅ API key valid." ;;
                400|401) echo "  ❌ Invalid API key." ;;
                *) echo "  ❌ Unexpected response (HTTP $http_code)." ;;
            esac
            echo "  Usage dashboard: https://aistudio.google.com/app/apikeys"
            ;;
        *)
            echo "  ℹ No verification API available for '$provider'."
            ;;
    esac
}

# ─── Show Session Usage ──────────────────────────────────────────────────────

show_usage() {
    echo "Session Token Usage:"
    echo ""

    if [ -d "$OPENCODE_SESSION_DIR" ]; then
        python3 -c "
import json, os, glob

sessions = sorted(glob.glob(os.path.join('$OPENCODE_SESSION_DIR', '*.json')), key=os.path.getmtime, reverse=True)[:20]
total_input = 0
total_output = 0
total_cost = 0
session_count = 0

for sf in sessions:
    try:
        data = json.load(open(sf))
        usage = data.get('usage', {})
        total_input += usage.get('input_tokens', 0)
        total_output += usage.get('output_tokens', 0)
        total_cost += usage.get('cost_microdollars', 0)
        session_count += 1
    except:
        pass

if session_count > 0:
    def fmt(n):
        if n >= 1000000: return f'{n/1000000:.1f}M'
        if n >= 1000: return f'{n/1000:.1f}K'
        return str(n)

    print(f'  Last {session_count} sessions:')
    print(f'  ┌─────────────────────────────────────────────┐')
    print(f'  │  Input:      {fmt(total_input):<12s} tokens          │')
    print(f'  │  Output:     {fmt(total_output):<12s} tokens          │')
    print(f'  │  Est. Cost:  \${total_cost/1000000:.2f}              │')
    print(f'  └─────────────────────────────────────────────┘')
else:
    print('  ℹ No session data found.')
    print('    Usage is displayed in the chat history during sessions.')
" 2>/dev/null
    else
        echo "  ℹ No session data directory found at $OPENCODE_SESSION_DIR"
        echo "    Usage is displayed in the chat history during sessions."
    fi
    echo ""

    echo "  Rate Limits (per provider):"
    echo "  ┌──────────────────────────────────────────────────┐"
    echo "  │  Anthropic:  Varies by tier (check dashboard)    │"
    echo "  │  OpenAI:     Free: 3 RPM / Paid: varies          │"
    echo "  │  Google:     Free: 15 RPM / Paid: higher         │"
    echo "  │  Groq:       Free: 14,400 RPM / Paid: 30,000     │"
    echo "  │  OpenRouter: Per-key limits (check activity)     │"
    echo "  └──────────────────────────────────────────────────┘"
}

# ─── List Sessions ────────────────────────────────────────────────────────────

list_sessions() {
    if [ ! -d "$OPENCODE_SESSION_DIR" ]; then
        echo "No session data found at $OPENCODE_SESSION_DIR"
        return
    fi

    echo "Recent Sessions (last 20):"
    echo ""
    printf "  %-24s %-20s %-12s %-12s %-10s\n" "Time" "Model" "Input" "Output" "Cost"
    printf "  %-24s %-20s %-12s %-12s %-10s\n" "----" "-----" "-----" "------" "----"

    python3 -c "
import json, os, glob
from datetime import datetime

sessions = sorted(glob.glob(os.path.join('$OPENCODE_SESSION_DIR', '*.json')), key=os.path.getmtime, reverse=True)[:20]

for sf in sessions:
    try:
        data = json.load(open(sf))
        usage = data.get('usage', {})
        model = data.get('model', 'unknown')
        ts = data.get('timestamp', data.get('created_at', ''))
        try:
            if ts:
                dt = datetime.fromisoformat(ts.replace('Z', '+00:00'))
                ts_str = dt.strftime('%Y-%m-%d %H:%M:%S')
            else:
                ts_str = datetime.fromtimestamp(os.path.getmtime(sf)).strftime('%Y-%m-%d %H:%M:%S')
        except:
            ts_str = 'unknown'

        inp = usage.get('input_tokens', 0)
        out = usage.get('output_tokens', 0)
        cost = usage.get('cost_microdollars', 0)

        def fmt(n):
            if n >= 1000000: return f'{n/1000000:.1f}M'
            if n >= 1000: return f'{n/1000:.1f}K'
            return str(n)

        model_short = model.split('/')[-1] if '/' in model else model
        if len(model_short) > 20: model_short = model_short[:17] + '...'

        print(f'  {ts_str:<24s} {model_short:<20s} {fmt(inp):<12s} {fmt(out):<12s} \${cost/1000000:<9.2f}')
    except:
        pass
" 2>/dev/null || echo "  Unable to parse session data."
}

# ─── Show Rate Limits ────────────────────────────────────────────────────────

show_rate_limits() {
    echo "Rate Limit Information by Provider:"
    echo ""
    echo "  ┌────────────────────────────────────────────────────────────┐"
    echo "  │  Provider     │ Free Tier          │ Paid Tier            │"
    echo "  ├───────────────┼────────────────────┼──────────────────────┤"
    echo "  │  Anthropic    │ N/A (API only)     │ Varies by tier       │"
    echo "  │  OpenAI       │ 3 RPM / 200k TPM   │ Varies by tier       │"
    echo "  │  Google       │ 15 RPM / 1M TPM    │ Higher limits        │"
    echo "  │  Groq         │ 14,400 RPM         │ 30,000 RPM           │"
    echo "  │  OpenRouter   │ Per-key limit      │ Configurable         │"
    echo "  │  xAI          │ Varies             │ Varies               │"
    echo "  └───────────────┴────────────────────┴──────────────────────┘"
    echo ""
    echo "  RPM = Requests Per Minute"
    echo "  TPM = Tokens Per Minute"
    echo ""
    echo "  Check your provider's dashboard for exact limits."
}

# ─── JSON Output ──────────────────────────────────────────────────────────────

output_json() {
    local config_file
    config_file=$(_find_config)

    python3 -c "
import json, os, glob, sys

config_file = sys.argv[1]

result = {
    'config_file': config_file or 'not found',
    'providers': {},
    'session_summary': {},
    'rate_limits': {
        'anthropic': 'varies by tier',
        'openai': '3 RPM free / varies paid',
        'google': '15 RPM free / higher paid',
        'groq': '14400 RPM free / 30000 paid',
        'openrouter': 'per-key limit'
    }
}

try:
    cfg = json.load(open(config_file))
    for name, pconf in cfg.get('provider', {}).items():
        opts = pconf.get('options', {})
        key = opts.get('apiKey', '')
        result['providers'][name] = {
            'enabled': name not in cfg.get('disabled_providers', []),
            'has_key': bool(key),
            'base_url': opts.get('baseURL', '')
        }
except:
    pass

try:
    sessions_dir = '$OPENCODE_SESSION_DIR'
    if os.path.isdir(sessions_dir):
        sessions = glob.glob(os.path.join(sessions_dir, '*.json'))
        total_input = total_output = total_cost = 0
        for sf in sessions[:20]:
            try:
                data = json.load(open(sf))
                usage = data.get('usage', {})
                total_input += usage.get('input_tokens', 0)
                total_output += usage.get('output_tokens', 0)
                total_cost += usage.get('cost_microdollars', 0)
            except:
                pass
        result['session_summary'] = {
            'sessions_analyzed': min(len(sessions), 20),
            'total_input_tokens': total_input,
            'total_output_tokens': total_output,
            'estimated_cost_usd': round(total_cost / 1000000, 4)
        }
except:
    pass

print(json.dumps(result, indent=2))
" "$config_file" 2>/dev/null || echo '{"error": "Unable to generate JSON output"}'
}

# ─── Full Status ──────────────────────────────────────────────────────────────

show_full_status() {
    echo "═══════════════════════════════════════════════════"
    echo "  OpenCode CLI — Status Report"
    echo "═══════════════════════════════════════════════════"
    echo ""

    local config_file
    config_file=$(_find_config)
    echo "Configuration:"
    if [ -n "$config_file" ]; then
        echo "  Config: $config_file"
        local model
        model=$(python3 -c "import json, sys; print(json.load(open(sys.argv[1])).get('model', 'not set'))" "$config_file" 2>/dev/null || echo "not set")
        echo "  Model:  $model"
    else
        echo "  ⚠ No config file found"
    fi
    echo ""

    check_providers "$config_file"
    echo ""
    show_usage
    echo ""

    echo "Usage dashboards:"
    echo "  Anthropic:  https://console.anthropic.com/settings/usage"
    echo "  OpenAI:     https://platform.openai.com/usage"
    echo "  Google:     https://aistudio.google.com/app/apikeys"
    echo "  Groq:       https://console.groq.com/"
    echo "  OpenRouter: https://openrouter.ai/activity"
}

# ─── Main ─────────────────────────────────────────────────────────────────────

ACTION=""
ACCOUNT=""
PROVIDER_NAME=""

while [ $# -gt 0 ]; do
    case "$1" in
        --providers|--usage|--sessions|--rate-limits|--json|--full)
            ACTION="$1"
            shift
            ;;
        --provider)
            ACTION="--provider"
            if [ -z "${2:-}" ]; then
                echo "❌ Error: Provider name required."
                exit 1
            fi
            PROVIDER_NAME="$2"
            shift 2
            ;;
        --account)
            if [ -z "${2:-}" ]; then
                echo "❌ Error: Account name required."
                exit 1
            fi
            ACCOUNT="$2"
            shift 2
            ;;
        --help|-h)
            usage
            ;;
        -*)
            echo "❌ Unknown option: $1"
            usage
            ;;
        *)
            if [ -z "$ACCOUNT" ]; then
                ACCOUNT="$1"
            fi
            shift
            ;;
    esac
done

if [ -n "$ACCOUNT" ]; then
    if ! _load_account "$ACCOUNT"; then
        exit 1
    fi
fi

case "${ACTION:---full}" in
    --providers)
        check_providers "" "$PROVIDER_NAME"
        ;;
    --usage)
        show_usage
        ;;
    --sessions)
        list_sessions
        ;;
    --provider)
        check_providers "" "$PROVIDER_NAME"
        echo ""
        verify_provider "" "$PROVIDER_NAME"
        ;;
    --rate-limits)
        show_rate_limits
        ;;
    --json)
        output_json
        ;;
    ""|--full)
        show_full_status
        ;;
    *)
        echo "❌ Unknown action: $ACTION"
        usage
        ;;
esac
