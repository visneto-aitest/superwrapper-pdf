#!/usr/bin/env bash
# qwen-status.sh - Check provider auth, token usage, and rate limits for Qwen Code CLI
#
# Qwen Code has no native usage command. This script:
#   1. Checks modelProviders configuration status
#   2. Verifies API keys by querying provider APIs
#   3. Parses session data for token usage
#   4. Displays rate limit information
#
# Usage:
#   qwen-status.sh                       # Show full status
#   qwen-status.sh <account>             # Status using specific account
#   qwen-status.sh --providers           # Show provider config only
#   qwen-status.sh --usage               # Show token usage summary
#   qwen-status.sh --sessions            # List recent sessions
#   qwen-status.sh --provider <name>     # Check specific provider
#   qwen-status.sh --rate-limits         # Show rate limit info
#   qwen-status.sh --json                # Output as JSON

set -euo pipefail

QWEN_ACCOUNTS_DIR="${QWEN_ACCOUNTS_DIR:-${HOME}/.config/qwen/accounts}"
QWEN_CONFIG_DIR="${HOME}/.qwen"
QWEN_SETTINGS="${QWEN_CONFIG_DIR}/settings.json"
QWEN_SESSION_DIR="${HOME}/.local/share/qwen/sessions"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/lib/common.sh" ]; then
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/lib/common.sh"
else
    _mask_key() { local v="$1" l=${#1}; if [ "$l" -gt 12 ]; then printf '%s' "${v:0:4}****${v: -4}"; elif [ "$l" -gt 0 ]; then printf '%s' "****(masked)"; else printf '%s' "(not set)"; fi; }
    _format_tokens() { local c="$1"; if [ "$c" -ge 1000000 ] 2>/dev/null; then printf '%.1fM' "$(echo "scale=1;$c/1000000" | bc 2>/dev/null || echo "$c")"; elif [ "$c" -ge 1000 ] 2>/dev/null; then printf '%.1fK' "$(echo "scale=1;$c/1000" | bc 2>/dev/null || echo "$c")"; else echo "$c"; fi; }
fi

# ─── Load account ────────────────────────────────────────────────────────────

_load_account() {
    local name="$1"
    local account_file="$QWEN_ACCOUNTS_DIR/$name.env"

    if [ ! -f "$account_file" ]; then
        echo "❌ Account '$name' not found at $account_file"
        echo "  Create it with: qwen-env create $name"
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
Qwen Code CLI — Status & Usage Checker

Usage: qwen-status.sh [options]
       qwen-status.sh <account-name> [options]

Options:
  <account-name>        Load credentials from this account
  --providers           Show modelProviders config only
  --usage               Show token usage summary
  --sessions            List recent sessions with token counts
  --provider <name>     Check specific provider
  --rate-limits         Show rate limit information
  --json                Output full status as JSON
  --help, -h            Show this help

Note: Qwen Code has no native usage command.
      Usage is tracked by upstream providers.
USAGE
    exit 0
}

# ─── Check Providers ─────────────────────────────────────────────────────────

check_providers() {
    local specific="${1:-}"

    if [ ! -f "$QWEN_SETTINGS" ]; then
        echo "⚠ No settings.json found at $QWEN_SETTINGS"
        echo "  Run 'qwen' to create default configuration."
        return 1
    fi

    echo "Model Providers:"
    echo ""

    python3 -c "
import json, os, re, sys

try:
    cfg = json.load(open(sys.argv[1]))
    mp = cfg.get('modelProviders', {})
    region = cfg.get('codingPlan', {}).get('region', 'default')

    print(f'  Region: {region}')
    print()

    specific = '$specific'

    for auth_type in sorted(mp.keys()):
        models = mp[auth_type]
        if not isinstance(models, list):
            continue
        if specific and auth_type != specific:
            continue

        print(f'  📡 {auth_type}')
        for m in models:
            mid = m.get('id', '?')
            env_key = m.get('envKey', '?')
            base_url = m.get('baseUrl', '')

            val = os.environ.get(env_key, '')
            if val:
                key_status = f'{env_key} = {val[:4]}****{val[-4:]} ✅'
            else:
                key_status = f'{env_key} = (not set) ⚠️'

            print(f'    • {mid}')
            print(f'      {key_status}')
            if base_url:
                print(f'      URL: {base_url}')
        print()

except Exception as e:
    print(f'  ❌ Error parsing settings.json: {e}')
    sys.exit(1)
" "$QWEN_SETTINGS" 2>/dev/null
}

# ─── Verify Provider ─────────────────────────────────────────────────────────

verify_provider() {
    local provider="$1"
    local api_key="${2:-}"

    if [ -z "$api_key" ]; then
        api_key=$(python3 -c "
import json, os, sys
try:
    cfg = json.load(open(sys.argv[1]))
    mp = cfg.get('modelProviders', {})
    provider = sys.argv[2]
    if provider in mp:
        for m in mp[provider]:
            env_key = m.get('envKey', '')
            if env_key:
                val = os.environ.get(env_key, '')
                if val:
                    print(val)
                    break
except:
    pass
" "$QWEN_SETTINGS" "$provider" 2>/dev/null)
    fi

    if [ -z "$api_key" ]; then
        echo "  ⚠ No API key found for provider '$provider'."
        return 0
    fi

    echo "  Verifying $provider API key..."
    case "$provider" in
        openai)
            local response
            response=$(curl -s -w "\n%{http_code}" -H "Authorization: Bearer $api_key" "https://api.openai.com/v1/models" 2>/dev/null) || { echo "  ❌ Failed to connect."; return; }
            local http_code; http_code=$(echo "$response" | tail -1)
            case "$http_code" in 200) echo "  ✅ Valid." ;; 401) echo "  ❌ Invalid." ;; 429) echo "  ⚠ Rate limited." ;; *) echo "  ❌ HTTP $http_code." ;; esac
            ;;
        anthropic)
            local response
            response=$(curl -s -w "\n%{http_code}" -H "x-api-key: $api_key" -H "anthropic-version: 2023-06-01" -H "Content-Type: application/json" -d '{"model":"claude-sonnet-4-20250514","max_tokens":1,"messages":[{"role":"user","content":"hi"}]}' "https://api.anthropic.com/v1/messages" 2>/dev/null) || { echo "  ❌ Failed to connect."; return; }
            local http_code; http_code=$(echo "$response" | tail -1)
            case "$http_code" in 200) echo "  ✅ Valid." ;; 401|403) echo "  ❌ Invalid." ;; 429) echo "  ⚠ Rate limited." ;; *) echo "  ❌ HTTP $http_code." ;; esac
            ;;
        gemini)
            local response
            response=$(curl -s -w "\n%{http_code}" \
                -H "x-goog-api-key: $api_key" \
                "https://generativelanguage.googleapis.com/v1beta/models" 2>/dev/null) || { echo "  ❌ Failed to connect."; return; }
            local http_code; http_code=$(echo "$response" | tail -1)
            case "$http_code" in 200) echo "  ✅ Valid." ;; 400|401) echo "  ❌ Invalid." ;; *) echo "  ❌ HTTP $http_code." ;; esac
            ;;
        dashscope|bailian)
            echo "  ℤ DashScope/Bailian verification not available."
            echo "    Check: https://bailian.console.aliyun.com/"
            ;;
        qwen)
            echo "  ℤ Qwen API verification not available via public endpoint."
            echo "    Check: https://dashscope.console.aliyun.com/"
            ;;
        *)
            echo "  ℹ No verification endpoint for '$provider'."
            ;;
    esac
}

# ─── Show Usage ──────────────────────────────────────────────────────────────

show_usage() {
    echo "Session Token Usage:"
    echo ""

    if [ -d "$QWEN_SESSION_DIR" ]; then
        python3 -c "
import json, os, glob
sessions = sorted(glob.glob(os.path.join('$QWEN_SESSION_DIR', '*.json')), key=os.path.getmtime, reverse=True)[:20]
total_input = total_output = total_cost = session_count = 0
for sf in sessions:
    try:
        data = json.load(open(sf))
        usage = data.get('usage', {})
        total_input += usage.get('input_tokens', 0)
        total_output += usage.get('output_tokens', 0)
        total_cost += usage.get('cost_microdollars', 0) or usage.get('cost', 0)
        session_count += 1
    except: pass
if session_count > 0:
    def fmt(n):
        if n >= 1000000: return f'{n/1000000:.1f}M'
        if n >= 1000: return f'{n/1000:.1f}K'
        return str(n)
    cost_str = f'\${total_cost/1000000:.2f}' if total_cost >= 1000 else f'\${total_cost:.2f}'
    print(f'  Last {session_count} sessions:')
    print(f'  ┌─────────────────────────────────────────────┐')
    print(f'  │  Input:      {fmt(total_input):<12s} tokens          │')
    print(f'  │  Output:     {fmt(total_output):<12s} tokens          │')
    print(f'  │  Est. Cost:  {cost_str:<12s}               │')
    print(f'  └─────────────────────────────────────────────┘')
else:
    print('  ℹ No session data found.')
" 2>/dev/null
    else
        echo "  ℹ No session data directory at $QWEN_SESSION_DIR"
        echo "    Token usage is displayed in the chat history."
    fi
    echo ""

    echo "  Rate Limits (per provider):"
    echo "  ┌──────────────────────────────────────────────────┐"
    echo "  │  OpenAI:     Free: 3 RPM / Paid: varies          │"
    echo "  │  Anthropic:  Varies by tier                      │"
    echo "  │  DashScope:  Varies by model tier                │"
    echo "  │  Gemini:     Free: 15 RPM / Paid: higher         │"
    echo "  └──────────────────────────────────────────────────┘"
}

# ─── List Sessions ────────────────────────────────────────────────────────────

list_sessions() {
    if [ ! -d "$QWEN_SESSION_DIR" ]; then
        echo "No session data found at $QWEN_SESSION_DIR"
        return
    fi

    echo "Recent Sessions (last 20):"
    echo ""
    printf "  %-24s %-20s %-12s %-12s %-10s\n" "Time" "Model" "Input" "Output" "Cost"
    printf "  %-24s %-20s %-12s %-12s %-10s\n" "----" "-----" "-----" "------" "----"

    python3 -c "
import json, os, glob
from datetime import datetime
sessions = sorted(glob.glob(os.path.join('$QWEN_SESSION_DIR', '*.json')), key=os.path.getmtime, reverse=True)[:20]
for sf in sessions:
    try:
        data = json.load(open(sf))
        usage = data.get('usage', {})
        model = data.get('model', 'unknown')
        ts = data.get('timestamp', '')
        try:
            dt = datetime.fromisoformat(ts.replace('Z', '+00:00')) if ts else datetime.fromtimestamp(os.path.getmtime(sf))
            ts_str = dt.strftime('%Y-%m-%d %H:%M:%S')
        except: ts_str = 'unknown'
        inp = usage.get('input_tokens', 0)
        out = usage.get('output_tokens', 0)
        cost = usage.get('cost_microdollars', 0) or usage.get('cost', 0)
        cost_str = f'\${cost/1000000:.2f}' if cost >= 1000 else f'\${cost:.2f}'
        def fmt(n):
            if n >= 1000000: return f'{n/1000000:.1f}M'
            if n >= 1000: return f'{n/1000:.1f}K'
            return str(n)
        ms = model.split('/')[-1] if '/' in model else model
        if len(ms) > 20: ms = ms[:17] + '...'
        print(f'  {ts_str:<24s} {ms:<20s} {fmt(inp):<12s} {fmt(out):<12s} {cost_str:<10s}')
    except: pass
" 2>/dev/null || echo "  Unable to parse session data."
}

# ─── Rate Limits ──────────────────────────────────────────────────────────────

show_rate_limits() {
    echo "Rate Limit Information:"
    echo ""
    echo "  ┌────────────────────────────────────────────────────────────┐"
    echo "  │  Provider     │ Free Tier          │ Paid Tier            │"
    echo "  ├───────────────┼────────────────────┼──────────────────────┤"
    echo "  │  OpenAI       │ 3 RPM / 200k TPM   │ Varies by tier       │"
    echo "  │  Anthropic    │ N/A (API only)     │ Varies by tier       │"
    echo "  │  DashScope    │ Varies by model    │ Varies by tier       │"
    echo "  │  Gemini       │ 15 RPM / 1M TPM    │ Higher limits        │"
    echo "  │  Qwen         │ Varies             │ Varies               │"
    echo "  └───────────────┴────────────────────┴──────────────────────┘"
}

# ─── JSON Output ──────────────────────────────────────────────────────────────

output_json() {
    python3 -c "
import json, os, glob, sys
result = {
    'settings_file': sys.argv[1],
    'providers': {},
    'session_summary': {}
}
try:
    cfg = json.load(open(sys.argv[1]))
    mp = cfg.get('modelProviders', {})
    for auth_type, models in mp.items():
        if isinstance(models, list):
            result['providers'][auth_type] = [
                {'id': m.get('id', ''), 'envKey': m.get('envKey', ''), 'has_key': bool(os.environ.get(m.get('envKey', '')))}
                for m in models
            ]
except: pass
try:
    sd = sys.argv[2]
    if os.path.isdir(sd):
        sessions = glob.glob(os.path.join(sd, '*.json'))
        ti = to = tc = sc = 0
        for sf in sessions[:20]:
            try:
                d = json.load(open(sf)); u = d.get('usage', {})
                ti += u.get('input_tokens', 0); to += u.get('output_tokens', 0)
                tc += u.get('cost_microdollars', 0) or u.get('cost', 0); sc += 1
            except: pass
        result['session_summary'] = {'sessions_analyzed': sc, 'total_input_tokens': ti, 'total_output_tokens': to, 'estimated_cost_usd': round(tc/1000000, 4) if tc >= 1000 else round(tc, 4)}
except: pass
print(json.dumps(result, indent=2))
" "$QWEN_SETTINGS" "$QWEN_SESSION_DIR" 2>/dev/null || echo '{"error": "Unable to generate JSON"}'
}

# ─── Full Status ──────────────────────────────────────────────────────────────

show_full_status() {
    echo "═══════════════════════════════════════════════════"
    echo "  Qwen Code CLI — Status Report"
    echo "═══════════════════════════════════════════════════"
    echo ""

    echo "Configuration:"
    echo "  Settings: $QWEN_SETTINGS"
    if [ -f "$QWEN_SETTINGS" ]; then
        local region
        region=$(python3 -c "import json, sys; print(json.load(open(sys.argv[1])).get('codingPlan',{}).get('region','default'))" "$QWEN_SETTINGS" 2>/dev/null || echo "unknown")
        echo "  Region:   $region"
    else
        echo "  ⚠ Not found"
    fi
    echo ""

    check_providers
    echo ""
    show_usage
    echo ""

    echo "Provider dashboards:"
    echo "  OpenAI:     https://platform.openai.com/usage"
    echo "  Anthropic:  https://console.anthropic.com/settings/usage"
    echo "  DashScope:  https://dashscope.console.aliyun.com/"
    echo "  Gemini:     https://aistudio.google.com/app/apikeys"
}

# ─── Main ─────────────────────────────────────────────────────────────────────

ACTION=""
ACCOUNT=""
PROVIDER_NAME=""

while [ $# -gt 0 ]; do
    case "$1" in
        --providers|--usage|--sessions|--rate-limits|--json|--full) ACTION="$1"; shift ;;
        --provider) ACTION="--provider"; PROVIDER_NAME="${2:-}"; shift 2 ;;
        --account) ACCOUNT="${2:-}"; shift 2 ;;
        --help|-h) usage ;;
        -*) echo "❌ Unknown option: $1"; usage ;;
        *) if [ -z "$ACCOUNT" ]; then ACCOUNT="$1"; fi; shift ;;
    esac
done

if [ -n "$ACCOUNT" ]; then
    if ! _load_account "$ACCOUNT"; then exit 1; fi
fi

case "${ACTION:---full}" in
    --providers) check_providers "$PROVIDER_NAME" ;;
    --usage) show_usage ;;
    --sessions) list_sessions ;;
    --provider) check_providers "$PROVIDER_NAME"; echo ""; verify_provider "$PROVIDER_NAME" ;;
    --rate-limits) show_rate_limits ;;
    --json) output_json ;;
    ""|--full) show_full_status ;;
    *) echo "❌ Unknown action: $ACTION"; usage ;;
esac
