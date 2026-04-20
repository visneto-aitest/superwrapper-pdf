#!/usr/bin/env bash
# claude-env.sh - Environment-based account switcher for Claude Code CLI
#
# Manages multiple Claude Code accounts using environment variable files.
# Supports API key auth, AWS Bedrock, Google Vertex AI, and Microsoft Foundry.
#
# Usage:
#   claude-env.sh list                        List all accounts
#   claude-env.sh create <name>               Create new account config
#   claude-env.sh show <name>                 Show account details (keys masked)
#   claude-env.sh edit <name>                 Edit account in $EDITOR
#   claude-env.sh validate <name>             Validate config syntax
#   claude-env.sh <name>                      Export vars to current shell
#   claude-env.sh <name> claude [args...]     Run claude with account
#
# Examples:
#   claude-env.sh create work
#   claude-env.sh create bedrock
#   claude-env.sh work                        # Export vars
#   claude-env.sh work claude                 # Run claude with work account
#   claude-env.sh bedrock claude              # Run with AWS Bedrock account

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

CLAUDE_ACCOUNTS_DIR="${CLAUDE_ACCOUNTS_DIR:-${HOME}/.config/claude/accounts}"

# ─── Known Claude Code environment variables ──────────────────────────────────

CLAUDE_PROVIDER_VARS=(
    "ANTHROPIC_API_KEY"
    "ANTHROPIC_AUTH_TOKEN"
    "CLAUDE_CODE_OAUTH_TOKEN"
    "ANTHROPIC_MODEL"
    "CLAUDE_CODE_SUBAGENT_MODEL"
    "CLAUDE_CODE_MAX_OUTPUT_TOKENS"
    "MAX_THINKING_TOKENS"
    # AWS Bedrock
    "CLAUDE_CODE_USE_BEDROCK"
    "AWS_ACCESS_KEY_ID"
    "AWS_SECRET_ACCESS_KEY"
    "AWS_REGION"
    "CLOUD_ML_REGION"
    "CLAUDE_CODE_SKIP_BEDROCK_AUTH"
    # Google Vertex AI
    "CLAUDE_CODE_USE_VERTEX"
    "GOOGLE_CLOUD_PROJECT"
    # Microsoft Foundry
    "CLAUDE_CODE_USE_FOUNDRY"
    # Network / Proxy
    "HTTP_PROXY"
    "HTTPS_PROXY"
    "NO_PROXY"
    "CLAUDE_CODE_CLIENT_CERT"
    "CLAUDE_CODE_CLIENT_KEY"
    # Debug
    "ANTHROPIC_LOG"
    "DISABLE_AUTOUPDATER"
    "DISABLE_TELEMETRY"
)

# Sensitive vars to mask (all of them, basically)
CLAUDE_SECRET_VARS=(
    "ANTHROPIC_API_KEY"
    "ANTHROPIC_AUTH_TOKEN"
    "CLAUDE_CODE_OAUTH_TOKEN"
    "AWS_ACCESS_KEY_ID"
    "AWS_SECRET_ACCESS_KEY"
    "CLAUDE_CODE_CLIENT_CERT"
    "CLAUDE_CODE_CLIENT_KEY"
)

# ─── Helpers ──────────────────────────────────────────────────────────────────

_hash_string() {
    printf '%s' "$1" | shasum -a 256 2>/dev/null | cut -d' ' -f1 || \
    printf '%s' "$1" | sha256sum 2>/dev/null | cut -d' ' -f1 || \
    echo "unknown"
}

_get_editor() {
    echo "${EDITOR:-${VISUAL:-nano}}"
}

# Safely grep a key from an env file (avoids set -eo pipefail issues)
_grep_env_key() {
    local key="$1"
    local file="$2"
    local result=""
    result=$(grep -E "^${key}=" "$file" 2>/dev/null | head -1 | cut -d'=' -f2-) || result=""
    printf '%s' "$result"
}



_validate_json() {
    local file="$1"
    if command -v python3 &>/dev/null; then
        if ! python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$file" 2>/dev/null; then
            return 1
        fi
    elif command -v jq &>/dev/null; then
        if ! jq empty "$file" 2>/dev/null; then
            return 1
        fi
    fi
    return 0
}

_mask_value() {
    local val="$1"
    local len=${#val}
    if [ "$len" -gt 12 ]; then
        echo "${val:0:4}****${val: -4} (${len} chars)"
    elif [ "$len" -gt 0 ]; then
        echo "****(masked)"
    else
        echo "(not set)"
    fi
}

_is_secret_var() {
    local var="$1"
    for known in "${CLAUDE_SECRET_VARS[@]}"; do
        [ "$var" = "$known" ] && return 0
    done
    return 1
}

# ─── Usage ────────────────────────────────────────────────────────────────────

usage() {
    cat << 'USAGE'
Claude Code CLI Account Manager (Environment-based)

Usage: claude-env.sh <command> [arguments]

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
  claude-env.sh create work
  claude-env.sh work                       # Export vars for current shell
  claude-env.sh work claude                # Run claude with work account
  claude-env.sh edit work                  # Edit in $EDITOR
  claude-env.sh validate work              # Check config syntax
  DRY_RUN=1 claude-env.sh work claude      # Preview without running

Environment Variables (supported in account files):
  ANTHROPIC_API_KEY       Anthropic API key (direct billing)
  ANTHROPIC_MODEL         Override model (e.g., claude-sonnet-4-20250514)
  CLAUDE_CODE_OAUTH_TOKEN Long-lived OAuth token (1-year, for headless/CI)
  CLAUDE_CODE_USE_BEDROCK=1     Use AWS Bedrock
  AWS_ACCESS_KEY_ID             AWS access key
  AWS_SECRET_ACCESS_KEY         AWS secret key
  AWS_REGION                    AWS region
  CLAUDE_CODE_USE_VERTEX=1      Use Google Vertex AI
  GOOGLE_CLOUD_PROJECT          GCP project ID
  CLAUDE_CODE_USE_FOUNDRY=1     Use Microsoft Foundry
  ANTHROPIC_LOG=debug           Enable API request logging
  DISABLE_AUTOUPDATER=1         Disable auto-update
  EDITOR                        Preferred editor (default: nano)
USAGE
    exit 0
}

# ─── List Accounts ────────────────────────────────────────────────────────────

list_accounts() {
    if [ ! -d "$CLAUDE_ACCOUNTS_DIR" ]; then
        echo "No accounts found."
        echo "Create one with: claude-env.sh create <name>"
        return
    fi

    local has_accounts=false
    echo "Available accounts:"
    echo ""

    # Compute combined hash of current shell's secret vars
    local current_hash=""
    local combined=""
    for var in "${CLAUDE_SECRET_VARS[@]}"; do
        local val="${!var:-}"
        if [ -n "$val" ]; then
            combined="${combined}${var}=${val}:"
        fi
    done
    if [ -n "$combined" ]; then
        current_hash=$(_hash_string "$combined")
    fi

    shopt -s nullglob 2>/dev/null || true
    local files=("$CLAUDE_ACCOUNTS_DIR"/*.env)
    shopt -u nullglob 2>/dev/null || true

    for file in "${files[@]}"; do
        [ -f "$file" ] || continue
        has_accounts=true
        local name
        name=$(basename "$file" .env)

        # Detect active account via hash comparison on secret vars
        local marker=""
        if [ -n "$current_hash" ]; then
            local file_combined=""
            for var in "${CLAUDE_SECRET_VARS[@]}"; do
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

        # Determine provider mode
        local provider_mode="unknown"
        local bedrock_val
        bedrock_val=$(grep -E '^CLAUDE_CODE_USE_BEDROCK=' "$file" 2>/dev/null | head -1 | cut -d'=' -f2- || echo "")
        local vertex_val
        vertex_val=$(grep -E '^CLAUDE_CODE_USE_VERTEX=' "$file" 2>/dev/null | head -1 | cut -d'=' -f2- || echo "")
        local foundry_val
        foundry_val=$(grep -E '^CLAUDE_CODE_USE_FOUNDRY=' "$file" 2>/dev/null | head -1 | cut -d'=' -f2- || echo "")
        local api_key_val
        api_key_val=$(grep -E '^ANTHROPIC_API_KEY=' "$file" 2>/dev/null | head -1 | cut -d'=' -f2- || echo "")
        local oauth_token_val
        oauth_token_val=$(grep -E '^CLAUDE_CODE_OAUTH_TOKEN=' "$file" 2>/dev/null | head -1 | cut -d'=' -f2- || echo "")

        if [ "$bedrock_val" = "1" ]; then
            local region
            region=$(grep -E '^AWS_REGION=' "$file" 2>/dev/null | head -1 | cut -d'=' -f2- || echo "")
            provider_mode="bedrock/$region"
        elif [ "$vertex_val" = "1" ]; then
            local project
            project=$(grep -E '^GOOGLE_CLOUD_PROJECT=' "$file" 2>/dev/null | head -1 | cut -d'=' -f2- || echo "")
            provider_mode="vertex/$project"
        elif [ "$foundry_val" = "1" ]; then
            provider_mode="foundry"
        elif [ -n "$oauth_token_val" ]; then
            provider_mode="oauth/headless"
        elif [ -n "$api_key_val" ]; then
            local model
            model=$(grep -E '^ANTHROPIC_MODEL=' "$file" 2>/dev/null | head -1 | cut -d'=' -f2- || echo "")
            provider_mode="anthropic/${model:-default}"
        fi

        if [ -n "$provider_mode" ] && [ "$provider_mode" != "unknown" ]; then
            echo "  • ${name}${marker}  ($provider_mode)"
        else
            echo "  • ${name}${marker}"
        fi
    done

    if [ "$has_accounts" = false ]; then
        echo "No accounts found."
        echo "Create one with: claude-env.sh create <name>"
    fi

    echo ""
    echo "Accounts directory: $CLAUDE_ACCOUNTS_DIR"
}

# ─── Create Account ───────────────────────────────────────────────────────────

create_account() {
    local name="${1:-}"

    if [ -z "$name" ]; then
        echo "❌ Error: Account name required."
        echo "Usage: claude-env.sh create <name>"
        exit 1
    fi

    if [[ ! "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo "❌ Error: Account name can only contain letters, numbers, hyphens, and underscores."
        exit 1
    fi

    mkdir -p "$CLAUDE_ACCOUNTS_DIR"

    local file="$CLAUDE_ACCOUNTS_DIR/$name.env"

    if [ -f "$file" ]; then
        echo "❌ Error: Account '$name' already exists."
        echo "Edit it with: claude-env.sh edit $name"
        exit 1
    fi

    cat > "$file" << 'EOF'
# Claude Code Account Configuration
# Choose ONE auth method below and fill in credentials.

# ─── Option 1: Direct Anthropic API (recommended) ─────────────
# ANTHROPIC_API_KEY=sk-ant-your-key-here
# ANTHROPIC_MODEL=claude-sonnet-4-20250514

# ─── Option 2: OAuth Token (headless/CI/CD - 1-year validity) ─
# Generate with: claude setup-token
# Then paste the output token here
# CLAUDE_CODE_OAUTH_TOKEN=your-oauth-token-here
#
# Note: Requires Pro, Max, Team, or Enterprise subscription
# Scoped to inference only (no Remote Control sessions)
# Ignored when running Claude Code in --bare mode

# ─── Option 3: AWS Bedrock ────────────────────────────────────
# CLAUDE_CODE_USE_BEDROCK=1
# AWS_ACCESS_KEY_ID=AKIA...
# AWS_SECRET_ACCESS_KEY=...
# AWS_REGION=us-east-1
# CLOUD_ML_REGION=us-east-1
# CLAUDE_CODE_SKIP_BEDROCK_AUTH=1

# ─── Option 4: Google Vertex AI ───────────────────────────────
# CLAUDE_CODE_USE_VERTEX=1
# GOOGLE_CLOUD_PROJECT=your-gcp-project-id
# CLOUD_ML_REGION=us-central1

# ─── Option 5: Microsoft Foundry ──────────────────────────────
# CLAUDE_CODE_USE_FOUNDRY=1
# (Uses Azure/Entra ID authentication)

# ─── Optional Overrides ───────────────────────────────────────
# CLAUDE_CODE_SUBAGENT_MODEL=claude-sonnet-4-20250514
# CLAUDE_CODE_MAX_OUTPUT_TOKENS=8192
# MAX_THINKING_TOKENS=32000

# ─── Debug / Behavior ─────────────────────────────────────────
# ANTHROPIC_LOG=debug              # Full API request logging
# DISABLE_AUTOUPDATER=1
# DISABLE_TELEMETRY=1
EOF

    chmod 600 "$file"

    echo "✅ Created account: $name"
    echo "Config file: $file"
    echo ""
    echo "Next steps:"
    echo "  1. Edit the file: claude-env.sh edit $name"
    echo "  2. Uncomment and set credentials for ONE auth method"
    echo "  3. Activate: claude-env.sh $name"
    echo "  4. Run: claude"
    echo ""
    echo "Or run directly: claude-env.sh $name claude"
}

# ─── Show Account ─────────────────────────────────────────────────────────────

show_account() {
    local name="${1:-}"
    local file="$CLAUDE_ACCOUNTS_DIR/$name.env"

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

    # Determine provider mode
    local bedrock_val vertex_val foundry_val api_key_val oauth_token_val
    bedrock_val=$(grep -E '^CLAUDE_CODE_USE_BEDROCK=' "$file" 2>/dev/null | head -1 | cut -d'=' -f2- || echo "")
    vertex_val=$(grep -E '^CLAUDE_CODE_USE_VERTEX=' "$file" 2>/dev/null | head -1 | cut -d'=' -f2- || echo "")
    foundry_val=$(grep -E '^CLAUDE_CODE_USE_FOUNDRY=' "$file" 2>/dev/null | head -1 | cut -d'=' -f2- || echo "")
    api_key_val=$(grep -E '^ANTHROPIC_API_KEY=' "$file" 2>/dev/null | head -1 | cut -d'=' -f2- || echo "")
    oauth_token_val=$(grep -E '^CLAUDE_CODE_OAUTH_TOKEN=' "$file" 2>/dev/null | head -1 | cut -d'=' -f2- || echo "")

    if [ "$bedrock_val" = "1" ]; then
        echo "  Provider: AWS Bedrock"
    elif [ "$vertex_val" = "1" ]; then
        echo "  Provider: Google Vertex AI"
    elif [ "$foundry_val" = "1" ]; then
        echo "  Provider: Microsoft Foundry"
    elif [ -n "$oauth_token_val" ]; then
        echo "  Provider: OAuth Token (headless/CI)"
    elif [ -n "$api_key_val" ]; then
        echo "  Provider: Anthropic (direct API)"
    else
        echo "  Provider: (not configured)"
    fi

    echo ""
    echo "Configured credentials:"

    local has_creds=false
    for var in "${CLAUDE_PROVIDER_VARS[@]}"; do
        local file_val
        file_val=$(grep -E "^${var}=" "$file" 2>/dev/null | head -1 | cut -d'=' -f2- || echo "")
        if [ -n "$file_val" ]; then
            has_creds=true
            if _is_secret_var "$var"; then
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
    local file="$CLAUDE_ACCOUNTS_DIR/$name.env"

    if [ ! -f "$file" ]; then
        echo "❌ Error: Account '$name' not found."
        echo "Create it with: claude-env.sh create $name"
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
    local file="$CLAUDE_ACCOUNTS_DIR/$name.env"

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

    # If account has a CLAUDE_CONFIG_DIR pointing to a profile, validate its settings.json
    local config_dir
    config_dir=$(grep -E '^CLAUDE_CONFIG_DIR=' "$file" 2>/dev/null | head -1 | cut -d'=' -f2- || echo "")
    if [ -n "$config_dir" ] && [ -f "$config_dir/settings.json" ]; then
        echo ""
        echo "Checking settings.json..."
        if _validate_json "$config_dir/settings.json"; then
            echo "✅ settings.json is valid."
        else
            echo "❌ settings.json has invalid JSON."
        fi
    fi
}

# ─── Load Account ─────────────────────────────────────────────────────────────

load_account() {
    local name="$1"
    local file="$CLAUDE_ACCOUNTS_DIR/$name.env"

    if [ ! -f "$file" ]; then
        echo "❌ Error: Account '$name' not found at $file"
        echo ""
        echo "Available accounts:"
        list_accounts
        exit 1
    fi

    set -a
    # shellcheck disable=SC1090
    source "$file"
    set +a

    echo "✅ Loaded account: $name"

    # Show active provider mode
    if [ "${CLAUDE_CODE_USE_BEDROCK:-}" = "1" ]; then
        echo "  Provider: AWS Bedrock (${AWS_REGION:-us-east-1})"
    elif [ "${CLAUDE_CODE_USE_VERTEX:-}" = "1" ]; then
        echo "  Provider: Google Vertex AI (${GOOGLE_CLOUD_PROJECT:-unknown})"
    elif [ "${CLAUDE_CODE_USE_FOUNDRY:-}" = "1" ]; then
        echo "  Provider: Microsoft Foundry"
    elif [ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]; then
        echo "  Provider: OAuth Token (headless)"
    elif [ -n "${ANTHROPIC_API_KEY:-}" ]; then
        echo "  Provider: Anthropic (direct API)"
    fi

    if [ -n "${ANTHROPIC_MODEL:-}" ]; then
        echo "  Model: $ANTHROPIC_MODEL"
    fi

    # Check OAuth token status
    if [ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]; then
        local token_len=${#CLAUDE_CODE_OAUTH_TOKEN}
        echo "  OAuth Token: $(_mask_value "$CLAUDE_CODE_OAUTH_TOKEN")"
    fi

    if [ -n "${CLAUDE_CONFIG_DIR:-}" ]; then
        echo "  Config Dir: $CLAUDE_CONFIG_DIR"
    fi

    echo ""
    echo "Environment variables exported to current shell."
    echo "Run 'claude' to start with this account."
}

# ─── Run With Account ─────────────────────────────────────────────────────────

run_with_account() {
    local name="$1"
    shift

    local file="$CLAUDE_ACCOUNTS_DIR/$name.env"

    if [ ! -f "$file" ]; then
        echo "❌ Error: Account '$name' not found at $file"
        exit 1
    fi

    # Validate directory permissions before sourcing
    local dir_perms
    if stat -f '%A' "$CLAUDE_ACCOUNTS_DIR" 2>/dev/null; then
        dir_perms=$(stat -f '%A' "$CLAUDE_ACCOUNTS_DIR")
    elif stat -c '%a' "$CLAUDE_ACCOUNTS_DIR" 2>/dev/null; then
        dir_perms=$(stat -c '%a' "$CLAUDE_ACCOUNTS_DIR")
    fi
    if [ "${dir_perms:-}" != "600" ] && [ "${dir_perms:-}" != "700" ]; then
        echo "❌ Error: Accounts directory has unsafe permissions: ${dir_perms:-unknown}"
        exit 1
    fi

    (
        set -a
        # shellcheck disable=SC1090
        source "$file"
        set +a

        if [ $# -eq 0 ]; then
            echo "❌ Error: No command specified."
            echo "Usage: claude-env.sh $name <command> [args...]"
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
        if [ -f "$CLAUDE_ACCOUNTS_DIR/$1.env" ]; then
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
