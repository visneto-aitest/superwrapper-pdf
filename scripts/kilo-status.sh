#!/usr/bin/env bash
# kilo-status.sh - Check provider auth, token usage, and rate limits for Kilo CLI
#
# Kilo CLI has no native usage command. This script:
#   1. Checks provider authentication status from kilo.jsonc
#   2. Verifies API keys by checking {env:VAR} resolution
#   3. Checks Kilo Gateway balance via API (if applicable)
#   4. Parses session data for token usage
#   5. Displays rate limit information
#
# Usage:
#   kilo-status.sh                       # Show full status
#   kilo-status.sh <account>             # Status using specific account
#   kilo-status.sh --balance             # Check Kilo Pass balance only
#   kilo-status.sh --usage               # Show session token usage only
#   kilo-status.sh --sessions            # List recent sessions with token counts
#   kilo-status.sh --provider <name>     # Check specific provider status
#   kilo-status.sh --rate-limits         # Show rate limit info
#   kilo-status.sh --json                # Output as JSON

set -euo pipefail

KILO_ACCOUNTS_DIR="${KILO_ACCOUNTS_DIR:-${HOME}/.config/kilo/accounts}"
KILO_CONFIG_DIR="${HOME}/.config/kilo"
KILO_SETTINGS="${KILO_CONFIG_DIR}/kilo.jsonc"
KILO_AUTH_FILE="${HOME}/.local/share/kilo/auth.json"
KILO_SESSION_DIR="${HOME}/.local/share/kilo/sessions"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/lib/common.sh" ]; then
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/lib/common.sh"
else
    _mask_key() { local v="$1" l=${#1}; if [ "$l" -gt 12 ]; then printf '%s' "${v:0:4}****${v: -4}"; elif [ "$l" -gt 0 ]; then printf '%s' "****(masked)"; else printf '%s' "(not set)"; fi; }
    _format_tokens() { local c="$1"; if [ "$c" -ge 1000000 ] 2>/dev/null; then printf '%.1fM' "$(echo "scale=1;$c/1000000" | bc 2>/dev/null || echo "$c")"; elif [ "$c" -ge 1000 ] 2>/dev/null; then printf '%.1fK' "$(echo "scale=1;$c/1000" | bc 2>/dev/null || echo "$c")"; else echo "$c"; fi; }
    _format_cost() { local md="$1"; if [ -n "$md" ] && [ "$md" != "null" ]; then printf '$%.2f' "$(echo "scale=2;$md/1000000" | bc 2>/dev/null || echo "0.00")"; else echo "N/A"; fi; }
fi

# ─── Load account credentials ────────────────────────────────────────────────

_load_account() {
    local name="$1"
    local account_file="$KILO_ACCOUNTS_DIR/$name.env"

    if [ ! -f "$account_file" ]; then
        echo "❌ Account '$name' not found at $account_file"
        echo "  Create it with: kilo-env.sh create $name"
        echo "  Or list accounts: kilo-env.sh list"
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
Kilo CLI — Status & Usage Checker

Usage: kilo-status.sh [options]
       kilo-status.sh <account-name> [options]

Options:
  <account-name>        Load credentials from this account
  --account <name>      Same as positional account name
  (no flags)            Show full status (balance + usage + providers)
  --balance             Check Kilo Pass balance only
  --usage               Show session token usage summary
  --sessions            List recent sessions with token counts
  --provider <name>     Check specific provider auth status
  --rate-limits         Show rate limit information
  --json                Output full status as JSON
  --help, -h            Show this help

Examples:
  kilo-status.sh                    # Full status (current shell creds)
  kilo-status.sh work               # Full status using "work" account
  kilo-status.sh work --balance     # Check balance for "work" account
  kilo-status.sh --balance          # Check balance (current shell creds)
  kilo-status.sh --json             # JSON output

Note: Kilo CLI has no native usage/billing command.
      Config file: ~/.config/kilo/kilo.jsonc
      API keys use {env:VAR_NAME} syntax — resolved from shell environment.
USAGE
    exit 0
}

# ─── Check Configuration ─────────────────────────────────────────────────────

check_config() {
    echo "Configuration:"
    echo "  Config: $KILO_SETTINGS"

    if [ -f "$KILO_SETTINGS" ]; then
        if _validate_json "$KILO_SETTINGS"; then
            echo "  Syntax:  ✅ valid"
        else
            echo "  Syntax:  ❌ invalid JSON"
        fi

        local model
        model=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("model", "not set"))' "$KILO_SETTINGS" 2>/dev/null || echo "unknown")
        echo "  Model:   $model"

        # Check if active profile is set
        if [ -f "$KILO_CONFIG_DIR/.active_profile" ]; then
            local active
            active=$(cat "$KILO_CONFIG_DIR/.active_profile")
            echo "  Profile: $active"
        fi
    else
        echo "  ⚠ Config file not found"
    fi
}

# ─── Check Kilo Pass Balance ─────────────────────────────────────────────────

check_balance() {
    local api_key="${KILO_API_KEY:-}"

    # If no direct env var, try to find a kilo gateway key from any provider var
    if [ -z "$api_key" ]; then
        # KILO_API_KEY is the canonical var for gateway access
        echo "ℹ KILO_API_KEY not set in environment."
        echo "  Balance check requires KILO_API_KEY env var."
        echo "  Load an account first: kilo-env.sh <name>"
        return 0
    fi

    # Check if this is a Kilo Pass / Gateway key
    if [[ ! "$api_key" =~ ^kilo_ ]] && [[ ! "$api_key" =~ ^sk- ]]; then
        echo "ℹ API key format does not appear to be a Kilo Pass key."
        echo "  Balance check is only available for Kilo Gateway accounts."
        echo "  For direct provider keys (OpenAI, Anthropic, etc.), check"
        echo "  the provider's web dashboard for usage/billing."
        return 0
    fi

    # Query Kilo Gateway balance
    echo "Checking Kilo Pass balance..."
    local response
    response=$(curl -s -w "\n%{http_code}" \
        -H "Authorization: Bearer $api_key" \
        -H "Content-Type: application/json" \
        "https://app.kilo.ai/api/v1/balance" 2>/dev/null) || {
        echo "❌ Failed to connect to Kilo Gateway."
        echo "  Check your API key and network connection."
        return 1
    }

    local http_code
    http_code=$(echo "$response" | tail -1)
    local body
    body=$(echo "$response" | sed '$d')

    if [ "$http_code" = "200" ]; then
        python3 -c '
import json, sys
try:
    data = json.loads(sys.argv[1])
    balance = data.get("balance", {})
    print("┌─────────────────────────────────────┐")
    print("│       Kilo Pass Balance             │")
    print("├─────────────────────────────────────┤")
    credits = balance.get("credits", 0)
    print(f"│  Credits:      {credits:>10.2f}       │")
    used = balance.get("used_credits", 0)
    print(f"│  Used:         {used:>10.2f}       │")
    total = balance.get("total_credits", 0)
    print(f"│  Total:        {total:>10.2f}       │")
    currency = balance.get("currency", "USD")
    print(f"│  Currency:     {currency:>10s}       │")
    print("└─────────────────────────────────────┘")
except Exception as e:
    print(f"  Response parse error: {e}")
' "$body" 2>/dev/null || echo "  Response: $body"
    elif [ "$http_code" = "402" ]; then
        echo "❌ Balance is $0.00 — credits exhausted."
        local buy_url
        buy_url=$(echo "$body" | python3 -c "import json,sys; print(json.load(sys.stdin).get('buyCreditsUrl', 'N/A'))" 2>/dev/null || echo "N/A")
        echo "  Add credits: $buy_url"
    elif [ "$http_code" = "401" ]; then
        echo "❌ Invalid API key or unauthorized."
        echo "  Run 'kilo auth' to re-authenticate."
    elif [ "$http_code" = "429" ]; then
        echo "⚠ Rate limited (HTTP 429)."
        echo "  Free tier: 200 requests per hour per IP."
        echo "  Wait and retry, or upgrade to Kilo Pass."
    else
        echo "❌ Unexpected response (HTTP $http_code)"
        echo "  $body"
    fi
}

# ─── Check Provider Auth Status ──────────────────────────────────────────────

check_providers() {
    local specific_provider="${1:-}"

    if [ ! -f "$KILO_SETTINGS" ]; then
        echo "⚠ No config file found at $KILO_SETTINGS"
        return
    fi

    echo "Provider Status:"
    echo ""

    python3 -c '
import json, os, re, sys

try:
    cfg = json.load(open(sys.argv[1]))
    providers = cfg.get("provider", {})
    disabled = set(cfg.get("disabled_providers", []))
    enabled = cfg.get("enabled_providers", list(providers.keys()))

    specific = sys.argv[2] if len(sys.argv) > 2 else ""
    if specific:
        if specific not in providers:
            available = ", ".join(providers.keys())
            print("Provider '{}' not found in config.".format(specific))
            print("   Available: {}".format(available))
            sys.exit(1)
        providers = {specific: providers[specific]}
        enabled = [specific]
        disabled = set()

    for name in sorted(providers.keys()):
        pconf = providers[name]
        opts = pconf.get("options", {})
        key = opts.get("apiKey", "")
        status_icon = "✅" if name in enabled else "⏸️"
        if name in disabled:
            status_icon = "❌"

        if not key:
            key_status = "(OAuth - from auth.json)"
        elif key.startswith("{env:"):
            env_var = re.match(r"\{env:(\w+)\}", key)
            if env_var:
                var_name = env_var.group(1)
                val = os.environ.get(var_name, "")
                if val:
                    key_status = f"env:{var_name}={val[:4]}****{val[-4:]}"
                else:
                    key_status = f"env:{var_name}=(not set)"
            else:
                key_status = key
        elif key:
            key_status = f"{key[:4]}****{key[-4:]}"
        else:
            key_status = "(using CLI auth / OAuth)"

        base_url = opts.get("baseURL", "")
        print(f"  {status_icon} {name}: {key_status}")
        if base_url:
            print(f"      Endpoint: {base_url}")

    if not specific:
        print("")
        print("  ✅ = enabled  ❌ = disabled  ⏸️ = not in enabled_providers list")
except Exception as e:
    print(f"  Error parsing config: {e}")
' "$KILO_SETTINGS" "$specific_provider" 2>/dev/null

    # Show OAuth providers from auth.json that may not be in kilo.jsonc
    if [ -f "$KILO_AUTH_FILE" ] && [ -z "$specific_provider" ]; then
        echo ""
        echo "OAuth Providers (from auth.json):"
        python3 -c '
import json, sys
try:
    data = json.load(open(sys.argv[1]))
    found = False
    for name, entry in sorted(data.items()):
        ptype = entry.get("type", "")
        if ptype == "oauth":
            found = True
            expires = entry.get("expires", 0)
            if expires:
                from datetime import datetime
                exp_dt = datetime.fromtimestamp(expires / 1000)
                exp_str = exp_dt.strftime("%Y-%m-%d %H:%M")
                print(f"  ✅ {name} (expires: {exp_str})")
            else:
                print(f"  ✅ {name} (no expiry)")
    if not found:
        print("  (none)")
except Exception as e:
    print(f"  Error reading auth file: {e}")
' "$KILO_AUTH_FILE" 2>/dev/null
    fi

    # Check CLI OAuth auth file status
    if [ -f "$KILO_AUTH_FILE" ] && [ -z "$specific_provider" ]; then
        echo ""
        echo "CLI OAuth Status:"
        if _validate_json "$KILO_AUTH_FILE" 2>/dev/null; then
            local auth_size
            auth_size=$(wc -c < "$KILO_AUTH_FILE" | tr -d ' ')
            echo "  ✅ Auth file exists ($auth_size bytes)"
        else
            echo "  ❌ Auth file exists but has invalid JSON"
        fi
    fi
}

# ─── Show Session Token Usage ────────────────────────────────────────────────

show_usage() {
    echo "Session Token Usage:"
    echo ""

    if [ -d "$KILO_SESSION_DIR" ]; then
        local sessions_data
        sessions_data=$(python3 -c '
import json, os, glob, sys

sessions_dir = sys.argv[1]
sessions = sorted(glob.glob(os.path.join(sessions_dir, "*.json")), key=os.path.getmtime, reverse=True)
total_input = 0
total_output = 0
total_cache_write = 0
total_cache_hit = 0
total_cost = 0
session_count = 0

for sfile in sessions[:20]:
    try:
        data = json.load(open(sfile))
        usage = data.get("usage", {})
        inp = usage.get("input_tokens", 0)
        out = usage.get("output_tokens", 0)
        cw = usage.get("cache_write_tokens", 0)
        ch = usage.get("cache_hit_tokens", 0)
        cost = usage.get("cost_microdollars", 0)
        total_input += inp
        total_output += out
        total_cache_write += cw
        total_cache_hit += ch
        total_cost += cost
        session_count += 1
    except:
        pass

print(f"sessions={session_count}")
print(f"input={total_input}")
print(f"output={total_output}")
print(f"cache_write={total_cache_write}")
print(f"cache_hit={total_cache_hit}")
print(f"cost={total_cost}")
' "$KILO_SESSION_DIR" 2>/dev/null)

        if [ -n "$sessions_data" ]; then
            local session_count=0 total_input=0 total_output=0 total_cost=0
            local cache_write=0 cache_hit=0
            while IFS='=' read -r key value; do
                case "$key" in
                    sessions) session_count="$value" ;;
                    input) total_input="$value" ;;
                    output) total_output="$value" ;;
                    cache_write) cache_write="$value" ;;
                    cache_hit) cache_hit="$value" ;;
                    cost) total_cost="$value" ;;
                esac
            done <<< "$sessions_data"

            if [ "$session_count" -gt 0 ] 2>/dev/null; then
                echo "  Last $session_count sessions:"
                echo "  ┌─────────────────────────────────────────────┐"
                echo "  │  Input:      $(_format_tokens "$total_input") tokens           │"
                echo "  │  Output:     $(_format_tokens "$total_output") tokens           │"
                echo "  │  Cache Write: $(_format_tokens "$cache_write") tokens           │"
                echo "  │  Cache Hit:   $(_format_tokens "$cache_hit") tokens           │"
                echo "  │  Est. Cost:   $(_format_cost "$total_cost")               │"
                echo "  └─────────────────────────────────────────────┘"
            else
                echo "  ℹ No session data found."
            fi
        else
            echo "  ℹ Unable to parse session data."
        fi
    else
        echo "  ℹ No session data directory at $KILO_SESSION_DIR"
    fi
    echo ""

    echo "  Rate Limits:"
    echo "  ┌──────────────────────────────────────────────────┐"
    echo "  │  Free tier:  200 requests/5 hours per IP         │"
    echo "  │  Paid tier:  No gateway-enforced limits          │"
    echo "  │  Provider:   Varies by upstream (OpenAI, etc.)   │"
    echo "  └──────────────────────────────────────────────────┘"
}

# ─── List Sessions ────────────────────────────────────────────────────────────

list_sessions() {
    if [ ! -d "$KILO_SESSION_DIR" ]; then
        echo "No session data found at $KILO_SESSION_DIR"
        echo "Sessions are created during interactive use."
        return
    fi

    echo "Recent Sessions (last 20):"
    echo ""
    printf "  %-24s %-20s %-12s %-12s %-10s\n" "Time" "Model" "Input" "Output" "Cost"
    printf "  %-24s %-20s %-12s %-12s %-10s\n" "----" "-----" "-----" "------" "----"

    python3 -c '
import json, os, glob, sys
from datetime import datetime

sessions_dir = sys.argv[1]
sessions = sorted(glob.glob(os.path.join(sessions_dir, "*.json")), key=os.path.getmtime, reverse=True)[:20]

for sfile in sessions:
    try:
        data = json.load(open(sfile))
        usage = data.get("usage", {})
        model = data.get("model", "unknown")
        ts = data.get("timestamp", data.get("created_at", ""))
        try:
            if ts:
                dt = datetime.fromisoformat(ts.replace("Z", "+00:00"))
                ts_str = dt.strftime("%Y-%m-%d %H:%M:%S")
            else:
                ts_str = datetime.fromtimestamp(os.path.getmtime(sfile)).strftime("%Y-%m-%d %H:%M:%S")
        except:
            ts_str = "unknown"

        inp = usage.get("input_tokens", 0)
        out = usage.get("output_tokens", 0)
        cost = usage.get("cost_microdollars", 0)

        def fmt(n):
            if n >= 1000000: return f"{n/1000000:.1f}M"
            if n >= 1000: return f"{n/1000:.1f}K"
            return str(n)

        cost_str = f"${cost/1000000:.2f}"
        model_short = model.split("/")[-1] if "/" in model else model
        if len(model_short) > 20: model_short = model_short[:17] + "..."

        print(f"  {ts_str:<24s} {model_short:<20s} {fmt(inp):<12s} {fmt(out):<12s} {cost_str:<10s}")
    except:
        pass
' "$KILO_SESSION_DIR" 2>/dev/null || echo "  Unable to parse session data."
}

# ─── Show Rate Limit Info ────────────────────────────────────────────────────

show_rate_limits() {
    echo "Rate Limit Information:"
    echo ""
    echo "  ┌────────────────────────────────────────────────────────────┐"
    echo "  │  Mode          │ Details                                  │"
    echo "  ├───────────────┼──────────────────────────────────────────┤"
    echo "  │  Free tier     │ 200 requests per 5 hours per IP          │"
    echo "  │  Kilo Pass     │ No gateway-enforced limits               │"
    echo "  │  Direct API    │ Varies by provider (OpenAI, Anthropic…)  │"
    echo "  │  Bedrock       │ Varies by AWS account quota              │"
    echo "  │  Vertex AI     │ Varies by GCP project quota              │"
    echo "  └───────────────┴──────────────────────────────────────────┘"
    echo ""
    echo "  Configure rate limits:"
    echo "    Settings > Advanced Settings > Rate Limit (seconds)"
    echo "    0 = disabled (default)"
    echo ""
    echo "  Dashboard:     https://app.kilo.ai/dashboard"
}

# ─── JSON Output ──────────────────────────────────────────────────────────────

output_json() {
    python3 -c '
import json, os, glob, sys

config_file = sys.argv[1]
auth_file = sys.argv[2]
sessions_dir = sys.argv[3]

result = {
    "config_file": config_file,
    "auth_file": auth_file,
    "providers": {},
    "session_summary": {},
    "rate_limits": {
        "free_tier": "200 requests per 5 hours per IP",
        "kilo_pass": "No gateway-enforced limits",
        "direct_api": "varies by provider"
    }
}

try:
    if os.path.isfile(config_file):
        cfg = json.load(open(config_file))
        result["model"] = cfg.get("model", "not set")
        for name, pconf in cfg.get("provider", {}).items():
            opts = pconf.get("options", {})
            key = opts.get("apiKey", "")
            result["providers"][name] = {
                "enabled": name not in cfg.get("disabled_providers", []),
                "has_key": bool(key),
                "uses_env_ref": key.startswith("{env:") if key else False,
                "base_url": opts.get("baseURL", "")
            }
except Exception:
    pass

try:
    if os.path.isfile(auth_file):
        result["oauth_auth"] = True
except Exception:
    pass

try:
    if os.path.isdir(sessions_dir):
        sessions = glob.glob(os.path.join(sessions_dir, "*.json"))
        total_input = 0
        total_output = 0
        total_cost = 0
        for sf in sessions[:20]:
            try:
                data = json.load(open(sf))
                usage = data.get("usage", {})
                total_input += usage.get("input_tokens", 0)
                total_output += usage.get("output_tokens", 0)
                total_cost += usage.get("cost_microdollars", 0)
            except:
                pass
        result["session_summary"] = {
            "sessions_analyzed": min(len(sessions), 20),
            "total_input_tokens": total_input,
            "total_output_tokens": total_output,
            "estimated_cost_usd": round(total_cost / 1000000, 4)
        }
except Exception:
    pass

print(json.dumps(result, indent=2))
' "$KILO_SETTINGS" "$KILO_AUTH_FILE" "$KILO_SESSION_DIR" 2>/dev/null || echo '{"error": "Unable to generate JSON output"}'
}

# ─── Full Status ──────────────────────────────────────────────────────────────

show_full_status() {
    echo "═══════════════════════════════════════════════════"
    echo "  Kilo CLI — Status Report"
    echo "═══════════════════════════════════════════════════"
    echo ""

    check_config
    echo ""
    check_balance
    echo ""
    check_providers
    echo ""
    show_usage
    echo ""

    echo "Dashboard: https://app.kilo.ai/dashboard"
    echo "Docs:      https://kilo.ai/docs/gateway/usage-and-billing"
}

# ─── Main ─────────────────────────────────────────────────────────────────────

ACTION=""
ACCOUNT=""
PROVIDER_NAME=""

while [ $# -gt 0 ]; do
    case "$1" in
        --balance|--usage|--sessions|--rate-limits|--json|--full)
            ACTION="$1"
            shift
            ;;
        --provider)
            ACTION="--provider"
            if [ -z "${2:-}" ]; then
                echo "❌ Error: Provider name required."
                echo "Usage: kilo-status.sh --provider <name>"
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
    if ! _load_account "$ACCOUNT"; then exit 1; fi
fi

case "${ACTION:---full}" in
    --balance) check_balance ;;
    --usage) show_usage ;;
    --sessions) list_sessions ;;
    --provider) check_providers "$PROVIDER_NAME" ;;
    --rate-limits) show_rate_limits ;;
    --json) output_json ;;
    ""|--full) show_full_status ;;
    *) echo "❌ Unknown action: $ACTION"; usage ;;
esac
