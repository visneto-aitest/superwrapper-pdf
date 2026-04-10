#!/usr/bin/env bash
# claude-status.sh - Check provider auth, token usage, and rate limits for Claude Code CLI
#
# Claude Code has no native usage command. This script:
#   1. Checks current provider auth status (Anthropic, Bedrock, Vertex, Foundry)
#   2. Verifies API keys by querying provider APIs
#   3. Parses session data for token usage
#   4. Displays rate limit information
#
# Usage:
#   claude-status.sh                       # Show full status
#   claude-status.sh <account>             # Status using specific account
#   claude-status.sh --providers           # Show provider auth status only
#   claude-status.sh --usage               # Show token usage summary
#   claude-status.sh --sessions            # List recent sessions
#   claude-status.sh --rate-limits         # Show rate limit info
#   claude-status.sh --json                # Output as JSON

set -euo pipefail

CLAUDE_ACCOUNTS_DIR="${CLAUDE_ACCOUNTS_DIR:-${HOME}/.config/claude/accounts}"
CLAUDE_CONFIG_DIR="${HOME}/.claude"
CLAUDE_STATE_FILE="${HOME}/.claude.json"
CLAUDE_SESSION_DIR="${HOME}/.local/share/claude/sessions"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/lib/common.sh" ]; then
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/lib/common.sh"
else
    _mask_key() { local v="$1" l=${#1}; if [ "$l" -gt 12 ]; then printf '%s' "${v:0:4}****${v: -4}"; elif [ "$l" -gt 0 ]; then printf '%s' "****(masked)"; else printf '%s' "(not set)"; fi; }
    _format_tokens() { local c="$1"; if [ "$c" -ge 1000000 ] 2>/dev/null; then printf '%.1fM' "$(echo "scale=1;$c/1000000" | bc 2>/dev/null || echo "$c")"; elif [ "$c" -ge 1000 ] 2>/dev/null; then printf '%.1fK' "$(echo "scale=1;$c/1000" | bc 2>/dev/null || echo "$c")"; else echo "$c"; fi; }
fi

# ─── Load account credentials ────────────────────────────────────────────────

_load_account() {
    local name="$1"
    local account_file="$CLAUDE_ACCOUNTS_DIR/$name.env"

    if [ ! -f "$account_file" ]; then
        echo "❌ Account '$name' not found at $account_file"
        echo "  Create it with: claude-env create $name"
        echo "  Or list accounts: claude-env list"
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
Claude Code CLI — Status & Usage Checker

Usage: claude-status.sh [options]
       claude-status.sh <account-name> [options]

Options:
  <account-name>        Load credentials from this account
  --providers           Show provider auth status only
  --usage               Show token usage summary
  --sessions            List recent sessions with token counts
  --rate-limits         Show rate limit information
  --json                Output full status as JSON
  --help, -h            Show this help

Note: Claude Code has no native usage command.
      Usage tracking is available via the Anthropic web dashboard.
USAGE
    exit 0
}

# ─── Check Provider Status ───────────────────────────────────────────────────

check_providers() {
    echo "Provider Status:"
    echo ""

    # Determine active provider mode
    if [ "${CLAUDE_CODE_USE_BEDROCK:-}" = "1" ]; then
        echo "  Mode: AWS Bedrock"
        echo "  Region: ${AWS_REGION:-us-east-1}"
        if [ -n "${AWS_ACCESS_KEY_ID:-}" ]; then
            echo "  AWS Key: $(_mask_key "$AWS_ACCESS_KEY_ID")"
        else
            echo "  AWS Key: (using IAM role / default credentials)"
        fi
        echo ""
    elif [ "${CLAUDE_CODE_USE_VERTEX:-}" = "1" ]; then
        echo "  Mode: Google Vertex AI"
        echo "  Project: ${GOOGLE_CLOUD_PROJECT:-not set}"
        echo "  Region: ${CLOUD_ML_REGION:-us-central1}"
        echo ""
    elif [ "${CLAUDE_CODE_USE_FOUNDRY:-}" = "1" ]; then
        echo "  Mode: Microsoft Foundry"
        echo "  Auth: Azure/Entra ID"
        echo ""
    elif [ -n "${ANTHROPIC_API_KEY:-}" ]; then
        echo "  Mode: Anthropic Direct API"
        echo "  API Key: $(_mask_key "$ANTHROPIC_API_KEY")"
        echo "  Model: ${ANTHROPIC_MODEL:-default}"
        echo ""
    else
        echo "  Mode: OAuth (subscription)"
        echo ""
    fi

    # Check state file
    if [ -f "$CLAUDE_STATE_FILE" ]; then
        local state_size
        state_size=$(wc -c < "$CLAUDE_STATE_FILE" | tr -d ' ')
        echo "  State file: $CLAUDE_STATE_FILE ($state_size bytes)"

        # Check for OAuth tokens
        local has_oauth
        has_oauth=$(python3 -c "
import json
try:
    data = json.load(open('$CLAUDE_STATE_FILE'))
    for key in data:
        if 'token' in key.lower() or 'auth' in key.lower() or 'oauth' in key.lower():
            print('yes')
            break
    else:
        print('no')
except:
    print('no')
" 2>/dev/null || echo "no")
        if [ "$has_oauth" = "yes" ]; then
            echo "  OAuth tokens: present ✅"
        else
            echo "  OAuth tokens: not found ⚠️"
        fi
    fi
    echo ""

    # Check CLAUDE_CONFIG_DIR
    if [ -n "${CLAUDE_CONFIG_DIR:-}" ] && [ "$CLAUDE_CONFIG_DIR" != "$HOME/.claude" ]; then
        echo "  Config Dir: $CLAUDE_CONFIG_DIR (custom)"
        if [ -d "$CLAUDE_CONFIG_DIR" ]; then
            echo "  ✓ Directory exists"
        else
            echo "  ❌ Directory not found"
        fi
    fi
}

# ─── Verify API Key ──────────────────────────────────────────────────────────

verify_api() {
    if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
        echo "  Verifying Anthropic API key..."
        local response
        response=$(curl -s -w "\n%{http_code}" \
            -H "x-api-key: $ANTHROPIC_API_KEY" \
            -H "anthropic-version: 2023-06-01" \
            -H "Content-Type: application/json" \
            -d '{"model":"claude-sonnet-4-20250514","max_tokens":1,"messages":[{"role":"user","content":"hi"}]}' \
            "https://api.anthropic.com/v1/messages" 2>/dev/null) || {
            echo "  ❌ Failed to connect to Anthropic API."
            return
        }
        local http_code
        http_code=$(echo "$response" | tail -1)
        case "$http_code" in
            200) echo "  ✅ API key valid." ;;
            401|403) echo "  ❌ Invalid API key." ;;
            429) echo "  ⚠ Rate limited." ;;
            *) echo "  ❌ Unexpected response (HTTP $http_code)." ;;
        esac
        echo "  Usage: https://console.anthropic.com/settings/usage"
    elif [ -n "${AWS_ACCESS_KEY_ID:-}" ]; then
        echo "  Verifying AWS Bedrock credentials..."
        if command -v aws &>/dev/null; then
            local aws_result
            aws_result=$(aws sts get-caller-identity 2>&1) && {
                echo "  ✅ AWS credentials valid."
                echo "  $aws_result" | head -1
            } || {
                echo "  ❌ AWS credentials invalid or not configured."
            }
        else
            echo "  ℹ AWS CLI not installed — cannot verify credentials."
        fi
        echo "  Usage: AWS Console > Bedrock"
    elif [ -n "${GOOGLE_CLOUD_PROJECT:-}" ]; then
        echo "  Verifying Vertex AI..."
        if command -v gcloud &>/dev/null; then
            gcloud auth print-access-token &>/dev/null && {
                echo "  ✅ Gcloud auth valid."
            } || {
                echo "  ❌ Gcloud auth not found. Run: gcloud auth login"
            }
        else
            echo "  ℹ gcloud CLI not installed — cannot verify credentials."
        fi
    else
        echo "  ℹ No API key or cloud credentials to verify."
        echo "    Using OAuth subscription mode."
    fi
}

# ─── Show Session Usage ──────────────────────────────────────────────────────

show_usage() {
    echo "Session Token Usage:"
    echo ""

    if [ -d "$CLAUDE_SESSION_DIR" ]; then
        python3 -c "
import json, os, glob

sessions = sorted(glob.glob(os.path.join('$CLAUDE_SESSION_DIR', '*.json')), key=os.path.getmtime, reverse=True)[:20]
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
        cost = usage.get('cost', 0)
        if cost == 0:
            cost = usage.get('cost_microdollars', 0)
        total_cost += cost
        session_count += 1
    except:
        pass

if session_count > 0:
    def fmt(n):
        if n >= 1000000: return f'{n/1000000:.1f}M'
        if n >= 1000: return f'{n/1000:.1f}K'
        return str(n)

    cost_display = f'\${total_cost:.2f}' if total_cost < 1000 else f'\${total_cost/1000000:.2f}'
    print(f'  Last {session_count} sessions:')
    print(f'  ┌─────────────────────────────────────────────┐')
    print(f'  │  Input:      {fmt(total_input):<12s} tokens          │')
    print(f'  │  Output:     {fmt(total_output):<12s} tokens          │')
    print(f'  │  Est. Cost:  {cost_display:<12s}               │')
    print(f'  └─────────────────────────────────────────────┘')
else:
    print('  ℹ No session data found.')
    print('    Token usage is displayed in the chat history during sessions.')
" 2>/dev/null
    else
        echo "  ℹ No session data directory found at $CLAUDE_SESSION_DIR"
        echo "    Token usage is displayed in the chat history during sessions."
    fi
    echo ""

    echo "  Rate Limits:"
    echo "  ┌──────────────────────────────────────────────────┐"
    echo "  │  Subscription:  No enforced limits              │"
    echo "  │  API Key:       Varies by tier                   │"
    echo "  │  Bedrock:       Varies by AWS account            │"
    echo "  │  Vertex AI:     Varies by GCP project            │"
    echo "  └──────────────────────────────────────────────────┘"
}

# ─── List Sessions ────────────────────────────────────────────────────────────

list_sessions() {
    if [ ! -d "$CLAUDE_SESSION_DIR" ]; then
        echo "No session data found at $CLAUDE_SESSION_DIR"
        return
    fi

    echo "Recent Sessions (last 20):"
    echo ""
    printf "  %-24s %-20s %-12s %-12s %-10s\n" "Time" "Model" "Input" "Output" "Cost"
    printf "  %-24s %-20s %-12s %-12s %-10s\n" "----" "-----" "-----" "------" "----"

    python3 -c "
import json, os, glob
from datetime import datetime

sessions = sorted(glob.glob(os.path.join('$CLAUDE_SESSION_DIR', '*.json')), key=os.path.getmtime, reverse=True)[:20]

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
        cost = usage.get('cost', 0)
        if cost == 0:
            cost = usage.get('cost_microdollars', 0)
        cost_str = f'\${cost:.2f}' if cost < 1000 else f'\${cost/1000000:.2f}'

        def fmt(n):
            if n >= 1000000: return f'{n/1000000:.1f}M'
            if n >= 1000: return f'{n/1000:.1f}K'
            return str(n)

        model_short = model.split('/')[-1] if '/' in model else model
        if len(model_short) > 20: model_short = model_short[:17] + '...'

        print(f'  {ts_str:<24s} {model_short:<20s} {fmt(inp):<12s} {fmt(out):<12s} {cost_str:<10s}')
    except:
        pass
" 2>/dev/null || echo "  Unable to parse session data."
}

# ─── Show Rate Limits ────────────────────────────────────────────────────────

show_rate_limits() {
    echo "Rate Limit Information:"
    echo ""
    echo "  ┌────────────────────────────────────────────────────────────┐"
    echo "  │  Mode          │ Details                                  │"
    echo "  ├───────────────┼──────────────────────────────────────────┤"
    echo "  │  Subscription  │ No enforced limits                       │"
    echo "  │  API Key       │ Varies by plan (check dashboard)         │"
    echo "  │  AWS Bedrock   │ Varies by AWS account quota              │"
    echo "  │  Vertex AI     │ Varies by GCP project quota              │"
    echo "  │  Foundry       │ Varies by Azure subscription             │"
    echo "  └───────────────┴──────────────────────────────────────────┘"
    echo ""
    echo "  Usage dashboard: https://console.anthropic.com/settings/usage"
}

# ─── JSON Output ──────────────────────────────────────────────────────────────

output_json() {
    python3 -c "
import json, os, glob

result = {
    'config_dir': os.environ.get('CLAUDE_CONFIG_DIR', '$CLAUDE_CONFIG_DIR'),
    'state_file': '$CLAUDE_STATE_FILE',
    'provider_mode': 'unknown',
    'session_summary': {}
}

# Determine provider mode
if os.environ.get('CLAUDE_CODE_USE_BEDROCK') == '1':
    result['provider_mode'] = f'bedrock ({os.environ.get(\"AWS_REGION\", \"us-east-1\")})'
elif os.environ.get('CLAUDE_CODE_USE_VERTEX') == '1':
    result['provider_mode'] = f'vertex ({os.environ.get(\"GOOGLE_CLOUD_PROJECT\", \"unknown\")})'
elif os.environ.get('CLAUDE_CODE_USE_FOUNDRY') == '1':
    result['provider_mode'] = 'foundry'
elif os.environ.get('ANTHROPIC_API_KEY'):
    result['provider_mode'] = 'anthropic-api'
else:
    result['provider_mode'] = 'oauth-subscription'

# Parse sessions
try:
    sessions_dir = '$CLAUDE_SESSION_DIR'
    if os.path.isdir(sessions_dir):
        sessions = glob.glob(os.path.join(sessions_dir, '*.json'))
        total_input = total_output = total_cost = 0
        for sf in sessions[:20]:
            try:
                data = json.load(open(sf))
                usage = data.get('usage', {})
                total_input += usage.get('input_tokens', 0)
                total_output += usage.get('output_tokens', 0)
                cost = usage.get('cost', 0) or usage.get('cost_microdollars', 0)
                total_cost += cost
            except:
                pass
        result['session_summary'] = {
            'sessions_analyzed': min(len(sessions), 20),
            'total_input_tokens': total_input,
            'total_output_tokens': total_output,
            'estimated_cost_usd': round(total_cost / 1000000, 4) if total_cost >= 1000 else round(total_cost, 4)
        }
except:
    pass

print(json.dumps(result, indent=2))
" 2>/dev/null || echo '{"error": "Unable to generate JSON output"}'
}

# ─── Full Status ──────────────────────────────────────────────────────────────

show_full_status() {
    echo "═══════════════════════════════════════════════════"
    echo "  Claude Code CLI — Status Report"
    echo "═══════════════════════════════════════════════════"
    echo ""

    echo "Configuration:"
    echo "  Config Dir: ${CLAUDE_CONFIG_DIR}"
    if [ -d "$CLAUDE_CONFIG_DIR" ]; then
        if [ -f "$CLAUDE_CONFIG_DIR/settings.json" ]; then
            echo "  Settings: ✅"
        fi
        if [ -f "$CLAUDE_CONFIG_DIR/CLAUDE.md" ]; then
            local lines
            lines=$(wc -l < "$CLAUDE_CONFIG_DIR/CLAUDE.md" | tr -d ' ')
            echo "  CLAUDE.md: $lines lines"
        fi
    else
        echo "  ⚠ Config directory not found"
    fi
    echo ""

    check_providers
    echo ""
    verify_api
    echo ""
    show_usage
    echo ""

    echo "Usage dashboard: https://console.anthropic.com/settings/usage"
}

# ─── Main ─────────────────────────────────────────────────────────────────────

ACTION=""
ACCOUNT=""

while [ $# -gt 0 ]; do
    case "$1" in
        --providers|--usage|--sessions|--rate-limits|--json|--full)
            ACTION="$1"
            shift
            ;;
        --account)
            if [ -z "${2:-}" ]; then echo "❌ Error: Account name required."; exit 1; fi
            ACCOUNT="$2"; shift 2
            ;;
        --help|-h) usage ;;
        -*) echo "❌ Unknown option: $1"; usage ;;
        *) if [ -z "$ACCOUNT" ]; then ACCOUNT="$1"; fi; shift ;;
    esac
done

if [ -n "$ACCOUNT" ]; then
    if ! _load_account "$ACCOUNT"; then exit 1; fi
fi

case "${ACTION:---full}" in
    --providers) check_providers ;;
    --usage) show_usage ;;
    --sessions) list_sessions ;;
    --rate-limits) show_rate_limits ;;
    --json) output_json ;;
    ""|--full) show_full_status ;;
    *) echo "❌ Unknown action: $ACTION"; usage ;;
esac
