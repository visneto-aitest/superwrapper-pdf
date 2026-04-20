#!/usr/bin/env bash
# gemini-status.sh - Check auth, token usage, and rate limits for Gemini CLI
#
# Gemini CLI has no native usage command. This script:
#   1. Checks current auth mode (OAuth, API Key, Workspace, Service Account)
#   2. Verifies API key validity
#   3. Displays rate limit information
#
# Usage:
#   gemini-status.sh                       # Show full status
#   gemini-status.sh <account>             # Status using specific account
#   gemini-status.sh --auth                # Show auth status only
#   gemini-status.sh --verify              # Verify API key
#   gemini-status.sh --rate-limits         # Show rate limit info
#   gemini-status.sh --json                # Output as JSON

set -euo pipefail

GEMINI_ACCOUNTS_DIR="${GEMINI_ACCOUNTS_DIR:-${HOME}/.config/gemini/accounts}"
GEMINI_CONFIG_DIR="${HOME}/.gemini"
GEMINI_SETTINGS="${GEMINI_CONFIG_DIR}/settings.json"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/lib/common.sh" ]; then
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/lib/common.sh"
else
    _mask_key() { local v="$1" l=${#1}; if [ "$l" -gt 12 ]; then printf '%s' "${v:0:4}****${v: -4}"; elif [ "$l" -gt 0 ]; then printf '%s' "****(masked)"; else printf '%s' "(not set)"; fi; }
fi

# ─── Load account ────────────────────────────────────────────────────────────

_load_account() {
    local name="$1"
    local account_file="$GEMINI_ACCOUNTS_DIR/$name.env"

    if [ ! -f "$account_file" ]; then
        echo "❌ Account '$name' not found at $account_file"
        echo "  Create it with: gemini-env create $name"
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
Gemini CLI — Status & Usage Checker

Usage: gemini-status.sh [options]
       gemini-status.sh <account-name> [options]

Options:
  <account-name>        Load credentials from this account
  --auth                Show auth status only
  --verify              Verify API key validity
  --rate-limits         Show rate limit information
  --json                Output full status as JSON
  --help, -h            Show this help

Note: Gemini CLI has no native usage command.
      Usage tracking requires API key mode (not OAuth).
USAGE
    exit 0
}

# ─── Check Auth Status ───────────────────────────────────────────────────────

check_auth() {
    echo "Authentication Status:"
    echo ""

    if [ -n "${GEMINI_API_KEY:-}" ]; then
        echo "  Mode: API Key"
        echo "  Key: $(_mask_key "$GEMINI_API_KEY")"
    elif [ -n "${GOOGLE_APPLICATION_CREDENTIALS:-}" ]; then
        echo "  Mode: Service Account"
        echo "  Credentials: $GOOGLE_APPLICATION_CREDENTIALS"
        if [ -f "$GOOGLE_APPLICATION_CREDENTIALS" ]; then
            echo "  File: ✅ exists"
        else
            echo "  File: ❌ not found"
        fi
    elif [ -n "${GOOGLE_CLOUD_PROJECT:-}" ]; then
        echo "  Mode: Google Workspace"
        echo "  Project: $GOOGLE_CLOUD_PROJECT"
        if command -v gcloud &>/dev/null; then
            if gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null | grep -q .; then
                echo "  gcloud auth: ✅ active"
            else
                echo "  gcloud auth: ⚠️ no active account"
            fi
        else
            echo "  gcloud CLI: not installed"
        fi
    else
        echo "  Mode: OAuth (free tier)"
        echo "  Note: OAuth requires browser authentication."
        echo "  Run 'gemini' to trigger OAuth login if needed."
    fi

    if [ -n "${VERTEXAI_PROJECT:-}" ]; then
        echo ""
        echo "  Vertex AI:"
        echo "  Project: $VERTEXAI_PROJECT"
        echo "  Location: ${VERTEXAI_LOCATION:-us-central1}"
    fi

    if [ -n "${GEMINI_MODEL:-}" ]; then
        echo ""
        echo "  Model override: $GEMINI_MODEL"
    fi

    if [ -n "${GEMINI_REGION:-}" ]; then
        echo "  Region: $GEMINI_REGION"
    fi
    echo ""

    # Check settings.json
    if [ -f "$GEMINI_SETTINGS" ]; then
        echo "  Settings: $GEMINI_SETTINGS"
        local model
        model=$(python3 -c "import json, sys; print(json.load(open(sys.argv[1])).get('model', 'default'))" "$GEMINI_SETTINGS" 2>/dev/null || echo "unknown")
        echo "  Configured model: $model"
    else
        echo "  ⚠ No settings.json found at $GEMINI_SETTINGS"
    fi
}

# ─── Verify API Key ──────────────────────────────────────────────────────────

verify_key() {
    if [ -n "${GEMINI_API_KEY:-}" ]; then
        echo "Verifying Gemini API key..."
        local response
        response=$(curl -s --connect-timeout 10 --max-time 30 -w "\n%{http_code}" \
            -H "x-goog-api-key: $GEMINI_API_KEY" \
            "https://generativelanguage.googleapis.com/v1beta/models" 2>/dev/null) || {
            echo "  ❌ Failed to connect to Google AI Studio."
            return
        }
        local http_code
        http_code=$(echo "$response" | tail -1)
        case "$http_code" in
            200)
                echo "  ✅ API key valid."
                local model_count
                model_count=$(echo "$response" | sed '$d' | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d.get('models',[])))" 2>/dev/null || echo "unknown")
                echo "  Available models: $model_count"
                ;;
            400|401) echo "  ❌ Invalid API key." ;;
            429) echo "  ⚠ Rate limited." ;;
            *) echo "  ❌ Unexpected response (HTTP $http_code)." ;;
        esac
        echo "  Usage dashboard: https://aistudio.google.com/app/apikeys"
    elif [ -n "${GOOGLE_CLOUD_PROJECT:-}" ]; then
        echo "Verifying Workspace access..."
        if command -v gcloud &>/dev/null; then
            local project_info
            project_info=$(gcloud projects describe "$GOOGLE_CLOUD_PROJECT" --format="value(name)" 2>/dev/null) && {
                echo "  ✅ Project '$GOOGLE_CLOUD_PROJECT' accessible."
            } || {
                echo "  ❌ Cannot access project '$GOOGLE_CLOUD_PROJECT'."
            }
        else
            echo "  ℹ gcloud CLI not installed — cannot verify."
        fi
    elif [ -n "${GOOGLE_APPLICATION_CREDENTIALS:-}" ]; then
        echo "Verifying service account..."
        if [ -f "$GOOGLE_APPLICATION_CREDENTIALS" ]; then
            echo "  ✅ Credentials file exists."
            local email
            email=$(python3 -c "import json, sys; print(json.load(open(sys.argv[1])).get('client_email', 'unknown'))" "$GOOGLE_APPLICATION_CREDENTIALS" 2>/dev/null || echo "unknown")
            echo "  Service account: $email"
        else
            echo "  ❌ Credentials file not found."
        fi
    else
        echo "  ℹ No API key or credentials to verify."
        echo "    Using OAuth (free tier) — no verification needed."
    fi
}

# ─── Rate Limits ──────────────────────────────────────────────────────────────

show_rate_limits() {
    echo "Rate Limit Information:"
    echo ""
    echo "  ┌────────────────────────────────────────────────────────────┐"
    echo "  │  Mode           │ Limits                                  │"
    echo "  ├─────────────────┼─────────────────────────────────────────┤"
    echo "  │  OAuth (Free)   │ 15 RPM / 1M TPM / 1500 RPD             │"
    echo "  │  API Key (Free) │ 15 RPM / 1M TPM / 1500 RPD             │"
    echo "  │  API Key (Paid) │ Higher limits (check dashboard)         │"
    echo "  │  Vertex AI      │ Varies by GCP project quota             │"
    echo "  └─────────────────┴─────────────────────────────────────────┘"
    echo ""
    echo "  RPM = Requests Per Minute"
    echo "  TPM = Tokens Per Minute"
    echo "  RPD = Requests Per Day"
    echo ""
    echo "  Dashboard: https://aistudio.google.com/app/apikeys"
}

# ─── JSON Output ──────────────────────────────────────────────────────────────

output_json() {
    python3 -c "
import json, os, sys

result = {
    'auth_mode': 'unknown',
    'settings_file': sys.argv[1],
    'rate_limits': {
        'oauth_free': '15 RPM / 1M TPM / 1500 RPD',
        'api_key_free': '15 RPM / 1M TPM / 1500 RPD',
        'api_key_paid': 'higher (check dashboard)',
        'vertex_ai': 'varies by GCP project'
    }
}

if os.environ.get('GEMINI_API_KEY'):
    result['auth_mode'] = 'api-key'
elif os.environ.get('GOOGLE_APPLICATION_CREDENTIALS'):
    result['auth_mode'] = 'service-account'
elif os.environ.get('GOOGLE_CLOUD_PROJECT'):
    result['auth_mode'] = 'workspace'
elif os.environ.get('VERTEXAI_PROJECT'):
    result['auth_mode'] = 'vertex-ai'
else:
    result['auth_mode'] = 'oauth-free'

result['model_override'] = os.environ.get('GEMINI_MODEL', '')
result['region'] = os.environ.get('GEMINI_REGION', '')
result['vertex_project'] = os.environ.get('VERTEXAI_PROJECT', '')

try:
    cfg = json.load(open(sys.argv[1]))
    result['config_model'] = cfg.get('model', 'default')
    result['config_theme'] = cfg.get('theme', 'default')
except:
    pass

print(json.dumps(result, indent=2))
" "$GEMINI_SETTINGS" 2>/dev/null || echo '{"error": "Unable to generate JSON"}'
}

# ─── Full Status ──────────────────────────────────────────────────────────────

show_full_status() {
    echo "═══════════════════════════════════════════════════"
    echo "  Gemini CLI — Status Report"
    echo "═══════════════════════════════════════════════════"
    echo ""

    check_auth
    echo ""
    verify_key
    echo ""
    show_rate_limits
}

# ─── Main ─────────────────────────────────────────────────────────────────────

ACTION=""
ACCOUNT=""

while [ $# -gt 0 ]; do
    case "$1" in
        --auth|--verify|--rate-limits|--json|--full) ACTION="$1"; shift ;;
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
    --auth) check_auth ;;
    --verify) verify_key ;;
    --rate-limits) show_rate_limits ;;
    --json) output_json ;;
    ""|--full) show_full_status ;;
    *) echo "❌ Unknown action: $ACTION"; usage ;;
esac
