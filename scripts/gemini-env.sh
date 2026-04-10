#!/usr/bin/env bash
# gemini-env.sh - Environment-based account switcher for Gemini CLI
#
# Manages multiple Gemini CLI accounts using environment variable files.
# Supports API key auth (paid tier) and Google Cloud project configuration.
#
# Usage:
#   gemini-env.sh list                        List all accounts
#   gemini-env.sh create <name>               Create new account config
#   gemini-env.sh show <name>                 Show account details (keys masked)
#   gemini-env.sh edit <name>                 Edit account in $EDITOR
#   gemini-env.sh validate <name>             Validate config syntax
#   gemini-env.sh <name>                      Export vars to current shell
#   gemini-env.sh <name> gemini [args...]     Run gemini with account
#
# Examples:
#   gemini-env.sh create work
#   gemini-env.sh create personal
#   gemini-env.sh work                        # Export vars
#   gemini-env.sh work gemini                 # Run gemini with work account

set -euo pipefail

GEMINI_ACCOUNTS_DIR="${GEMINI_ACCOUNTS_DIR:-${HOME}/.config/gemini/accounts}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source shared library
if [ -f "$SCRIPT_DIR/../lib/common.sh" ]; then
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/../lib/common.sh"
else
    # Fallback: define minimal helpers inline
    _get_editor() { printf '%s' "${EDITOR:-${VISUAL:-nano}}"; }
    _hash_string() { printf '%s' "$1" | shasum -a 256 2>/dev/null | cut -d' ' -f1 || printf '%s' "$1" | sha256sum 2>/dev/null | cut -d' ' -f1 || echo "unknown"; }
    _mask_value() { local v="$1" l=${#1}; if [ "$l" -gt 12 ]; then printf '%s' "${v:0:4}****${v: -4} ($l chars)"; elif [ "$l" -gt 0 ]; then printf '%s' "****(masked)"; else printf '%s' "(not set)"; fi; }
    _validate_env_file() { local f="$1" ln=0 er=0; while IFS= read -r line || [ -n "$line" ]; do ln=$((ln+1)); [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue; if [[ ! "$line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then printf '  ⚠ Line %d: Invalid format\n' "$ln"; er=$((er+1)); fi; done < "$f"; [ "$er" -gt 0 ] && return 1; return 0; }
    _validate_json() { local f="$1"; if command -v python3 &>/dev/null; then python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$f" 2>/dev/null || return 1; elif command -v jq &>/dev/null; then jq empty "$f" 2>/dev/null || return 1; fi; return 0; }
    _dry_run() { if [ "${DRY_RUN:-0}" = "1" ]; then printf '🔍 [DRY RUN] Would execute: %s\n' "$*"; return 0; else "$@"; fi; }
    _grep_env_key() { local r=""; r=$(grep -E "^${1}=" "$2" 2>/dev/null | head -1 | cut -d'=' -f2-) || r=""; printf '%s' "$r"; }
fi

# ─── Gemini CLI environment variables ─────────────────────────────────────────

GEMINI_PROVIDER_VARS=(
    "GEMINI_API_KEY"
    "GOOGLE_CLOUD_PROJECT"
    "GOOGLE_APPLICATION_CREDENTIALS"
    "GEMINI_OAUTH_TOKEN"
    "GEMINI_REFRESH_TOKEN"
    "GEMINI_MODEL"
    "GEMINI_REGION"
    "GEMINI_TEMPERATURE"
    "GEMINI_MAX_OUTPUT_TOKENS"
    "GEMINI_SAFETY_SETTINGS"
    "VERTEXAI_PROJECT"
    "VERTEXAI_LOCATION"
)

GEMINI_SECRET_VARS=(
    "GEMINI_API_KEY"
    "GOOGLE_APPLICATION_CREDENTIALS"
    "GEMINI_OAUTH_TOKEN"
    "GEMINI_REFRESH_TOKEN"
)

# ─── Usage ────────────────────────────────────────────────────────────────────

usage() {
    cat << 'USAGE'
Gemini CLI Account Manager (Environment-based)

Usage: gemini-env.sh <command> [arguments]

Commands:
  list                  List available accounts
  create <name>         Create new account config
  show <name>           Show account configuration (keys masked)
  edit <name>           Edit account config in $EDITOR
  validate <name>       Validate account config syntax
  <name>                Export account env vars to current shell
  <name> <command>      Run command with account credentials

Flags:
  DRY_RUN=1             Preview actions without executing

Accounts directory: <dynamic>

Examples:
  gemini-env.sh create work
  gemini-env.sh work                       # Export vars for current shell
  gemini-env.sh work gemini                # Run gemini with work account
  gemini-env.sh edit work                  # Edit in $EDITOR
  gemini-env.sh validate work              # Check config syntax
  DRY_RUN=1 gemini-env.sh work gemini      # Preview without running

Environment Variables (supported in account files):
  GEMINI_API_KEY               API key for Gemini (paid/enterprise tier)
  GEMINI_OAUTH_TOKEN           OAuth access token (headless mode)
  GEMINI_REFRESH_TOKEN         OAuth refresh token (auto-renewal)
  GOOGLE_CLOUD_PROJECT         GCP project (required for Workspace accounts)
  GOOGLE_APPLICATION_CREDENTIALS  Path to service account JSON
  GEMINI_MODEL                 Default model override
  GEMINI_REGION                API region
  VERTEXAI_PROJECT             Vertex AI project (for Gemini via Vertex)
  VERTEXAI_LOCATION            Vertex AI location
  EDITOR                       Preferred editor (default: nano)

Note: Gemini CLI uses Google OAuth for free tier (no API key needed).
      Environment variable switching applies to API-key and Workspace modes.
USAGE
    exit 0
}

# ─── List Accounts ────────────────────────────────────────────────────────────

list_accounts() {
    if [ ! -d "$GEMINI_ACCOUNTS_DIR" ]; then
        echo "No accounts found."
        echo "Create one with: gemini-env.sh create <name>"
        return
    fi

    local has_accounts=false
    echo "Available accounts:"
    echo ""

    # Compute hash of current shell's secret vars
    local current_hash=""
    local combined=""
    for var in "${GEMINI_SECRET_VARS[@]}"; do
        local val="${!var:-}"
        if [ -n "$val" ]; then
            combined="${combined}${var}=${val}:"
        fi
    done
    if [ -n "$combined" ]; then
        current_hash=$(_hash_string "$combined")
    fi

    # Use nullglob-safe iteration
    shopt -s nullglob 2>/dev/null || true
    local files=("$GEMINI_ACCOUNTS_DIR"/*.env)
    shopt -u nullglob 2>/dev/null || true

    for file in "${files[@]}"; do
        [ -f "$file" ] || continue
        has_accounts=true
        local name
        name=$(basename "$file" .env)

        # Detect active account via hash comparison
        local marker=""
        if [ -n "$current_hash" ]; then
            local file_combined=""
            for var in "${GEMINI_SECRET_VARS[@]}"; do
                local file_val
                file_val=$(_grep_env_key "$var" "$file")
                if [ -n "$file_val" ]; then
                    file_combined="${file_combined}${var}=${file_val}:"
                fi
            done
            if [ -n "$file_combined" ]; then
                local file_hash
                file_hash=$(_hash_string "$file_combined")
                if [ "$current_hash" = "$file_hash" ]; then
                    marker=" ✓"
                fi
            fi
        fi

        # Show auth mode and model
        local auth_mode="oauth"
        local api_key_val
        api_key_val=$(_grep_env_key "GEMINI_API_KEY" "$file")
        local oauth_token_val
        oauth_token_val=$(_grep_env_key "GEMINI_OAUTH_TOKEN" "$file")
        local gcp_project
        gcp_project=$(_grep_env_key "GOOGLE_CLOUD_PROJECT" "$file")
        local model
        model=$(_grep_env_key "GEMINI_MODEL" "$file")

        if [ -n "$oauth_token_val" ]; then
            auth_mode="oauth-token"
        elif [ -n "$api_key_val" ]; then
            auth_mode="api-key"
        elif [ -n "$gcp_project" ]; then
            auth_mode="workspace"
        fi

        local info="$auth_mode"
        [ -n "$model" ] && info="$info → $model"
        [ -n "$gcp_project" ] && info="$info ($gcp_project)"

        echo "  • ${name}${marker}  ($info)"
    done

    if [ "$has_accounts" = false ]; then
        echo "No accounts found."
        echo "Create one with: gemini-env.sh create <name>"
    fi

    echo ""
    echo "Accounts directory: $GEMINI_ACCOUNTS_DIR"
}

# ─── Create Account ───────────────────────────────────────────────────────────

create_account() {
    local name="${1:-}"

    if [ -z "$name" ]; then
        echo "❌ Error: Account name required."
        echo "Usage: gemini-env.sh create <name>"
        exit 1
    fi

    if [[ ! "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo "❌ Error: Account name can only contain letters, numbers, hyphens, and underscores."
        exit 1
    fi

    mkdir -p "$GEMINI_ACCOUNTS_DIR"

    local file="$GEMINI_ACCOUNTS_DIR/$name.env"

    if [ -f "$file" ]; then
        echo "❌ Error: Account '$name' already exists."
        echo "Edit it with: gemini-env.sh edit $name"
        exit 1
    fi

    cat > "$file" << 'EOF'
# Gemini CLI Account Configuration
# Choose your authentication method below.

# ─── Option 1: API Key (paid/enterprise tier) ──────────────────
# GEMINI_API_KEY=ai-your-api-key-here

# ─── Option 2: OAuth Tokens (headless/non-interactive) ─────────
# For headless OAuth usage (alternative to interactive browser login)
# Generate tokens on an interactive machine, then copy here:
# GEMINI_OAUTH_TOKEN=your-access-token-here
# GEMINI_REFRESH_TOKEN=your-refresh-token-here
#
# Note: Access tokens expire hourly; refresh token auto-renews

# ─── Option 3: Google Workspace / GCP ──────────────────────────
# Required for Workspace accounts
# GOOGLE_CLOUD_PROJECT=your-gcp-project-id

# ─── Option 4: Service Account ─────────────────────────────────
# GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json

# ─── Vertex AI (alternative to direct Gemini API) ──────────────
# VERTEXAI_PROJECT=your-vertex-project
# VERTEXAI_LOCATION=us-central1

# ─── Model & Behavior Overrides (optional) ─────────────────────
# GEMINI_MODEL=gemini-2.5-pro
# GEMINI_REGION=us-central1
# GEMINI_TEMPERATURE=0.7
# GEMINI_MAX_OUTPUT_TOKENS=8192
EOF

    chmod 600 "$file"

    echo "✅ Created account: $name"
    echo "Config file: $file"
    echo ""
    echo "Next steps:"
    echo "  1. Edit the file: gemini-env.sh edit $name"
    echo "  2. Uncomment and set your credentials"
    echo "  3. Activate: gemini-env.sh $name"
    echo "  4. Run: gemini"
    echo ""
    echo "Or run directly: gemini-env.sh $name gemini"
}

# ─── Show Account ─────────────────────────────────────────────────────────────

show_account() {
    local name="${1:-}"
    local file="$GEMINI_ACCOUNTS_DIR/$name.env"

    if [ ! -f "$file" ]; then
        echo "❌ Error: Account '$name' not found."
        echo "Available accounts:"
        list_accounts
        exit 1
    fi

    echo "Account: $name"
    echo "File: $file"
    echo "Last modified: $(stat -f '%Sm' "$file" 2>/dev/null || stat -c '%y' "$file" 2>/dev/null || echo "unknown")"
    echo "---"

    # Determine auth mode
    local api_key_val oauth_token_val gcp_project svc_creds
    api_key_val=$(_grep_env_key "GEMINI_API_KEY" "$file")
    oauth_token_val=$(_grep_env_key "GEMINI_OAUTH_TOKEN" "$file")
    gcp_project=$(_grep_env_key "GOOGLE_CLOUD_PROJECT" "$file")
    svc_creds=$(_grep_env_key "GOOGLE_APPLICATION_CREDENTIALS" "$file")

    if [ -n "$oauth_token_val" ]; then
        echo "  Auth Mode: OAuth Token (headless)"
    elif [ -n "$api_key_val" ]; then
        echo "  Auth Mode: API Key"
    elif [ -n "$gcp_project" ]; then
        echo "  Auth Mode: Google Workspace ($gcp_project)"
    elif [ -n "$svc_creds" ]; then
        echo "  Auth Mode: Service Account"
    else
        echo "  Auth Mode: OAuth (free tier — no key configured)"
    fi

    local model
    model=$(_grep_env_key "GEMINI_MODEL" "$file")
    [ -n "$model" ] && echo "  Model: $model"

    echo ""
    echo "Configured credentials:"

    local has_creds=false
    for var in "${GEMINI_PROVIDER_VARS[@]}"; do
        local file_val
        file_val=$(_grep_env_key "$var" "$file")
        if [ -n "$file_val" ]; then
            has_creds=true
            # Check if this is a secret var
            local is_secret=false
            for sv in "${GEMINI_SECRET_VARS[@]}"; do
                [ "$var" = "$sv" ] && is_secret=true && break
            done
            if [ "$is_secret" = true ]; then
                echo "  $var: $(_mask_value "$file_val")"
            else
                echo "  $var: $file_val"
            fi
        fi
    done

    [ "$has_creds" = false ] && echo "  (no credentials configured)"
    echo "---"

    if ! _validate_env_file "$file" 2>/dev/null; then
        echo "⚠ Config has syntax warnings (see above)"
    fi
}

# ─── Edit Account ─────────────────────────────────────────────────────────────

edit_account() {
    local name="${1:-}"
    local file="$GEMINI_ACCOUNTS_DIR/$name.env"

    if [ ! -f "$file" ]; then
        echo "❌ Error: Account '$name' not found."
        echo "Create it with: gemini-env.sh create $name"
        exit 1
    fi

    local editor
    editor=$(_get_editor)

    echo "Opening $file in $editor..."
    "$editor" "$file"

    echo ""
    if _validate_env_file "$file"; then
        echo "✅ Config saved and validated."
    else
        echo "⚠ Config saved but has syntax warnings. Review above."
    fi
}

# ─── Validate Account ─────────────────────────────────────────────────────────

validate_account() {
    local name="${1:-}"
    local file="$GEMINI_ACCOUNTS_DIR/$name.env"

    if [ ! -f "$file" ]; then
        echo "❌ Error: Account '$name' not found."
        exit 1
    fi

    echo "Validating: $name"
    echo "File: $file"
    echo "---"

    if _validate_env_file "$file"; then
        echo "---"
        echo "✅ Config syntax is valid."
    else
        echo "---"
        echo "❌ Config has syntax errors (see above)."
        exit 1
    fi

    # Check service account JSON if referenced
    local svc_creds
    svc_creds=$(_grep_env_key "GOOGLE_APPLICATION_CREDENTIALS" "$file")
    if [ -n "$svc_creds" ] && [ -f "$svc_creds" ]; then
        echo ""
        echo "Checking service account JSON..."
        if _validate_json "$svc_creds"; then
            echo "✅ Service account file is valid JSON."
        else
            echo "❌ Service account file has invalid JSON."
        fi
    fi
}

# ─── Load Account ─────────────────────────────────────────────────────────────

load_account() {
    local name="$1"
    local file="$GEMINI_ACCOUNTS_DIR/$name.env"

    if [ ! -f "$file" ]; then
        echo "❌ Error: Account '$name' not found at $file"
        echo ""
        echo "Available accounts:"
        list_accounts
        exit 1
    fi

    set -a
    # shellcheck disable=SC1090,SC2154
    source "$file"
    set +a

    echo "✅ Loaded account: $name"

    # Determine auth mode
    if [ -n "${GEMINI_OAUTH_TOKEN:-}" ]; then
        echo "  Auth: OAuth Token (headless)"
        echo "  OAuth Token: $(_mask_value "$GEMINI_OAUTH_TOKEN")"
        [ -n "${GEMINI_REFRESH_TOKEN:-}" ] && echo "  Refresh Token: configured"
    elif [ -n "${GEMINI_API_KEY:-}" ]; then
        echo "  Auth: API Key"
    elif [ -n "${GOOGLE_CLOUD_PROJECT:-}" ]; then
        echo "  Auth: Workspace (${GOOGLE_CLOUD_PROJECT})"
    elif [ -n "${GOOGLE_APPLICATION_CREDENTIALS:-}" ]; then
        echo "  Auth: Service Account"
    else
        echo "  Auth: OAuth (free tier)"
    fi

    [ -n "${GEMINI_MODEL:-}" ] && echo "  Model: ${GEMINI_MODEL}"
    [ -n "${VERTEXAI_PROJECT:-}" ] && echo "  Vertex: ${VERTEXAI_PROJECT}"

    echo ""
    echo "Environment variables exported to current shell."
    echo "Run 'gemini' to start with this account."
}

# ─── Run With Account ─────────────────────────────────────────────────────────

run_with_account() {
    local name="$1"
    shift

    local file="$GEMINI_ACCOUNTS_DIR/$name.env"

    if [ ! -f "$file" ]; then
        echo "❌ Error: Account '$name' not found at $file"
        exit 1
    fi

    (
        set -a
        # shellcheck disable=SC1090
        source "$file"
        set +a

        if [ $# -eq 0 ]; then
            echo "❌ Error: No command specified."
            echo "Usage: gemini-env.sh $name <command> [args...]"
            exit 1
        fi

        exec "$@"
    )
}

# ─── Main ─────────────────────────────────────────────────────────────────────

case "${1:-}" in
    list)
        list_accounts
        ;;
    create)
        create_account "${2:-}"
        ;;
    show)
        show_account "${2:-}"
        ;;
    edit)
        edit_account "${2:-}"
        ;;
    validate)
        validate_account "${2:-}"
        ;;
    ""|--help|-h|help)
        usage
        ;;
    *)
        if [ -f "$GEMINI_ACCOUNTS_DIR/$1.env" ]; then
            if [ "${2:-}" = "" ]; then
                load_account "$1"
            else
                shift
                run_with_account "$@"
            fi
        else
            echo "❌ Unknown command or account: $1"
            echo ""
            usage
        fi
        ;;
esac
