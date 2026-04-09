#!/usr/bin/env bash
# opencode-env.sh - Environment-based account switcher for OpenCode CLI
#
# Manages multiple OpenCode accounts using environment variable files.
# Each account stores credentials for multiple providers (Anthropic, OpenAI, etc.)
# and optional config overrides.
#
# Usage:
#   opencode-env.sh list                        List all accounts
#   opencode-env.sh create <name>               Create new account config
#   opencode-env.sh show <name>                 Show account details (keys masked)
#   opencode-env.sh edit <name>                 Edit account in $EDITOR
#   opencode-env.sh validate <name>             Validate config syntax
#   opencode-env.sh <name>                      Export vars to current shell
#   opencode-env.sh <name> opencode [args...]   Run opencode with account
#
# Examples:
#   opencode-env.sh create work
#   opencode-env.sh create personal
#   opencode-env.sh work                        # Export vars
#   opencode-env.sh work opencode               # Run opencode with work account
#   opencode-env.sh personal opencode --model anthropic/claude-sonnet-4

set -euo pipefail

OPENCODE_ACCOUNTS_DIR="${OPENCODE_ACCOUNTS_DIR:-${HOME}/.config/opencode/accounts}"

# ─── Helpers ──────────────────────────────────────────────────────────────────

# Known OpenCode provider env vars
OPENCODE_PROVIDER_VARS=(
    "ANTHROPIC_API_KEY"
    "OPENAI_API_KEY"
    "GEMINI_API_KEY"
    "GROQ_API_KEY"
    "OPENROUTER_API_KEY"
    "XAI_API_KEY"
    "AZURE_OPENAI_ENDPOINT"
    "AZURE_OPENAI_API_KEY"
    "AWS_ACCESS_KEY_ID"
    "AWS_SECRET_ACCESS_KEY"
    "AWS_REGION"
    "GITHUB_TOKEN"
)

# Compute SHA256 hash of a string (portable)
_hash_string() {
    printf '%s' "$1" | shasum -a 256 2>/dev/null | cut -d' ' -f1 || \
    printf '%s' "$1" | sha256sum 2>/dev/null | cut -d' ' -f1 || \
    echo "unknown"
}

# Get configured editor
_get_editor() {
    echo "${EDITOR:-${VISUAL:-nano}}"
}

# Validate .env file syntax
_validate_env_file() {
    local file=$1
    local line_num=0
    local errors=0

    while IFS= read -r line || [ -n "$line" ]; do
        line_num=$((line_num + 1))
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        if [[ ! "$line" =~ ^[A-Z_]+= ]]; then
            echo "  ⚠ Line $line_num: Invalid format: ${line:0:50}"
            errors=$((errors + 1))
        fi
    done < "$file"

    return $errors
}

# Validate JSON syntax
_validate_json() {
    local file=$1
    if command -v python3 &>/dev/null; then
        if ! python3 -c "import json; json.load(open('$file'))" 2>/dev/null; then
            return 1
        fi
    elif command -v jq &>/dev/null; then
        if ! jq empty "$file" 2>/dev/null; then
            return 1
        fi
    fi
    return 0
}

# Mask a sensitive value (show first 4 + last 4)
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

# Check if a var name is a known provider credential
_is_provider_var() {
    local var="$1"
    for known in "${OPENCODE_PROVIDER_VARS[@]}"; do
        [ "$var" = "$known" ] && return 0
    done
    return 1
}

# ─── Usage ────────────────────────────────────────────────────────────────────

usage() {
    cat << 'USAGE'
OpenCode CLI Account Manager (Environment-based)

Usage: opencode-env.sh <command> [arguments]

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
  opencode-env.sh create work
  opencode-env.sh work                      # Export vars for current shell
  opencode-env.sh work opencode             # Run opencode with work account
  opencode-env.sh edit work                 # Edit in $EDITOR
  opencode-env.sh validate work             # Check config syntax
  DRY_RUN=1 opencode-env.sh work opencode   # Preview without running

Environment Variables (supported in account files):
  ANTHROPIC_API_KEY     Anthropic provider key
  OPENAI_API_KEY        OpenAI provider key
  GEMINI_API_KEY        Google Gemini key
  GROQ_API_KEY          Groq key
  OPENROUTER_API_KEY    OpenRouter key
  XAI_API_KEY           xAI (Grok) key
  AZURE_OPENAI_*        Azure OpenAI endpoint + key
  AWS_ACCESS_KEY_ID     AWS Bedrock credentials
  AWS_SECRET_ACCESS_KEY
  AWS_REGION
  OPENCODE_DEFAULT_PROVIDER  Route to specific provider
  OPENCODE_DEFAULT_MODEL     Default model string
  OPENCODE_CONFIG_CONTENT  Full JSON config override
  EDITOR                  Preferred editor (default: nano)
USAGE
    exit 0
}

# ─── List Accounts ────────────────────────────────────────────────────────────

list_accounts() {
    if [ ! -d "$OPENCODE_ACCOUNTS_DIR" ]; then
        echo "No accounts found."
        echo "Create one with: opencode-env.sh create <name>"
        return
    fi

    local has_accounts=false
    echo "Available accounts:"
    echo ""

    # Build hash map of current shell's provider keys (for active detection)
    declare -A current_hashes=()
    for var in "${OPENCODE_PROVIDER_VARS[@]}"; do
        local val="${!var:-}"
        if [ -n "$val" ]; then
            current_hashes["$var"]=$(_hash_string "$val")
        fi
    done

    for file in "$OPENCODE_ACCOUNTS_DIR"/*.env; do
        [ -f "$file" ] || continue
        has_accounts=true
        local name
        name=$(basename "$file" .env)

        # Detect active account via hash comparison
        local is_active=true
        for var in "${OPENCODE_PROVIDER_VARS[@]}"; do
            local file_val
            file_val=$(grep -E "^${var}=" "$file" 2>/dev/null | head -1 | cut -d'=' -f2- || echo "")
            local shell_val="${!var:-}"
            # Both must be set and match
            if [ -n "$file_val" ] && [ -n "$shell_val" ]; then
                local file_hash shell_hash
                file_hash=$(_hash_string "$file_val")
                shell_hash=$(_hash_string "$shell_val")
                if [ "$file_hash" != "$shell_hash" ]; then
                    is_active=false
                fi
            elif [ -n "$file_val" ] && [ -z "$shell_val" ]; then
                is_active=false
            fi
        done

        local marker=""
        [ "$is_active" = true ] && [ ${#current_hashes[@]} -gt 0 ] && marker=" ✓"

        # Show configured providers and model
        local providers=()
        local model=""
        for var in "${OPENCODE_PROVIDER_VARS[@]}"; do
            local val
            val=$(grep -E "^${var}=" "$file" 2>/dev/null | head -1 | cut -d'=' -f2- || echo "")
            if [ -n "$val" ]; then
                # Derive provider name from var
                case "$var" in
                    ANTHROPIC_API_KEY) providers+=("anthropic") ;;
                    OPENAI_API_KEY) providers+=("openai") ;;
                    GEMINI_API_KEY) providers+=("gemini") ;;
                    GROQ_API_KEY) providers+=("groq") ;;
                    OPENROUTER_API_KEY) providers+=("openrouter") ;;
                    XAI_API_KEY) providers+=("xai") ;;
                    AZURE_OPENAI_API_KEY) providers+=("azure") ;;
                    AWS_ACCESS_KEY_ID) providers+=("bedrock") ;;
                esac
            fi
        done

        model=$(grep -E "^OPENCODE_DEFAULT_MODEL=" "$file" 2>/dev/null | head -1 | cut -d'=' -f2- || echo "")
        local def_provider
        def_provider=$(grep -E "^OPENCODE_DEFAULT_PROVIDER=" "$file" 2>/dev/null | head -1 | cut -d'=' -f2- || echo "")

        local info=""
        if [ ${#providers[@]} -gt 0 ]; then
            info=$(IFS=','; echo "${providers[*]}")
        fi
        if [ -n "$def_provider" ] && [ -n "$model" ]; then
            info="$info → $def_provider/$model"
        elif [ -n "$model" ]; then
            info="$info → $model"
        fi

        if [ -n "$info" ]; then
            echo "  • ${name}${marker}  ($info)"
        else
            echo "  • ${name}${marker}"
        fi
    done

    if [ "$has_accounts" = false ]; then
        echo "No accounts found."
        echo "Create one with: opencode-env.sh create <name>"
    fi

    echo ""
    echo "Accounts directory: $OPENCODE_ACCOUNTS_DIR"
}

# ─── Create Account ───────────────────────────────────────────────────────────

create_account() {
    local name="${1:-}"

    if [ -z "$name" ]; then
        echo "❌ Error: Account name required."
        echo "Usage: opencode-env.sh create <name>"
        exit 1
    fi

    if [[ ! "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo "❌ Error: Account name can only contain letters, numbers, hyphens, and underscores."
        exit 1
    fi

    mkdir -p "$OPENCODE_ACCOUNTS_DIR"

    local file="$OPENCODE_ACCOUNTS_DIR/$name.env"

    if [ -f "$file" ]; then
        echo "❌ Error: Account '$name' already exists."
        echo "Edit it with: opencode-env.sh edit $name"
        exit 1
    fi

    cat > "$file" << 'EOF'
# OpenCode CLI Account Configuration
# Fill in credentials for the providers you use.
# Only set the keys for providers you want active.

# ─── Provider API Keys ───────────────────────────────────────────
# Anthropic (Claude)
# ANTHROPIC_API_KEY=sk-ant-your-key-here

# OpenAI (GPT)
# OPENAI_API_KEY=sk-proj-your-key-here

# Google Gemini
# GEMINI_API_KEY=ai-your-key-here

# Groq
# GROQ_API_KEY=gsk-your-key-here

# OpenRouter (multi-provider aggregator)
# OPENROUTER_API_KEY=sk-or-your-key-here

# xAI (Grok)
# XAI_API_KEY=xai-your-key-here

# ─── Azure OpenAI (if using Azure) ──────────────────────────────
# AZURE_OPENAI_ENDPOINT=https://your-resource.openai.azure.com
# AZURE_OPENAI_API_KEY=your-azure-key

# ─── AWS Bedrock (if using Bedrock) ─────────────────────────────
# AWS_ACCESS_KEY_ID=AKIA...
# AWS_SECRET_ACCESS_KEY=...
# AWS_REGION=us-east-1

# ─── GitHub Copilot (if using Copilot auth) ─────────────────────
# GITHUB_TOKEN=ghp_your-token

# ─── Default Routing ────────────────────────────────────────────
# Which provider/model to use by default
OPENCODE_DEFAULT_PROVIDER=anthropic
OPENCODE_DEFAULT_MODEL=claude-sonnet-4-20250514

# ─── Full Config Override (optional, advanced) ──────────────────
# Inject complete opencode.json config (overrides file-based config)
# OPENCODE_CONFIG_CONTENT='{"model":"anthropic/claude-sonnet-4","provider":{"anthropic":{"options":{"apiKey":"'"$ANTHROPIC_API_KEY"'"}}}}'
EOF

    chmod 600 "$file"

    echo "✅ Created account: $name"
    echo "Config file: $file"
    echo ""
    echo "Next steps:"
    echo "  1. Edit the file: opencode-env.sh edit $name"
    echo "  2. Uncomment and set your API keys"
    echo "  3. Activate: opencode-env.sh $name"
    echo "  4. Run: opencode"
    echo ""
    echo "Or run directly: opencode-env.sh $name opencode"
}

# ─── Show Account ─────────────────────────────────────────────────────────────

show_account() {
    local name="${1:-}"
    local file="$OPENCODE_ACCOUNTS_DIR/$name.env"

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

    # Show routing vars
    local def_provider def_model
    def_provider=$(grep -E '^OPENCODE_DEFAULT_PROVIDER=' "$file" 2>/dev/null | head -1 | cut -d'=' -f2- || echo "")
    def_model=$(grep -E '^OPENCODE_DEFAULT_MODEL=' "$file" 2>/dev/null | head -1 | cut -d'=' -f2- || echo "")
    [ -n "$def_provider" ] && echo "  Default Provider: $def_provider"
    [ -n "$def_model" ] && echo "  Default Model: $def_model"

    echo ""
    echo "Configured credentials:"

    # Show each provider key from file (masked, from file — not current env)
    local has_creds=false
    for var in "${OPENCODE_PROVIDER_VARS[@]}"; do
        local file_val
        file_val=$(grep -E "^${var}=" "$file" 2>/dev/null | head -1 | cut -d'=' -f2- || echo "")
        if [ -n "$file_val" ]; then
            has_creds=true
            local friendly_name="$var"
            case "$var" in
                ANTHROPIC_API_KEY) friendly_name="Anthropic" ;;
                OPENAI_API_KEY) friendly_name="OpenAI" ;;
                GEMINI_API_KEY) friendly_name="Gemini" ;;
                GROQ_API_KEY) friendly_name="Groq" ;;
                OPENROUTER_API_KEY) friendly_name="OpenRouter" ;;
                XAI_API_KEY) friendly_name="xAI (Grok)" ;;
                AZURE_OPENAI_ENDPOINT) friendly_name="Azure Endpoint" ;;
                AZURE_OPENAI_API_KEY) friendly_name="Azure Key" ;;
                AWS_ACCESS_KEY_ID) friendly_name="AWS Access Key" ;;
                AWS_SECRET_ACCESS_KEY) friendly_name="AWS Secret Key" ;;
                AWS_REGION) friendly_name="AWS Region" ;;
                GITHUB_TOKEN) friendly_name="GitHub Token" ;;
            esac
            echo "  $friendly_name: $(_mask_value "$file_val")"
        fi
    done

    [ "$has_creds" = false ] && echo "  (no credentials configured)"

    echo ""

    # Check for OPENCODE_CONFIG_CONTENT
    local has_config_content
    has_config_content=$(grep -c '^OPENCODE_CONFIG_CONTENT=' "$file" 2>/dev/null || echo "0")
    if [ "$has_config_content" -gt 0 ]; then
        echo "  ⚙ OPENCODE_CONFIG_CONTENT: set (full config override active)"
        echo ""
    fi

    echo "---"

    # Validate
    if ! _validate_env_file "$file" 2>/dev/null; then
        echo "⚠ Config has syntax warnings (see above)"
    fi
}

# ─── Edit Account ─────────────────────────────────────────────────────────────

edit_account() {
    local name="${1:-}"
    local file="$OPENCODE_ACCOUNTS_DIR/$name.env"

    if [ ! -f "$file" ]; then
        echo "❌ Error: Account '$name' not found."
        echo "Create it with: opencode-env.sh create $name"
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
    local file="$OPENCODE_ACCOUNTS_DIR/$name.env"

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

    # Also validate OPENCODE_CONFIG_CONTENT if present
    local config_content
    config_content=$(grep -E '^OPENCODE_CONFIG_CONTENT=' "$file" 2>/dev/null | head -1 | cut -d'=' -f2- || echo "")
    if [ -n "$config_content" ]; then
        echo ""
        echo "Checking OPENCODE_CONFIG_CONTENT..."
        # Write to temp file for validation
        local tmp
        tmp=$(mktemp)
        printf '%s' "$config_content" > "$tmp"
        if _validate_json "$tmp"; then
            echo "✅ OPENCODE_CONFIG_CONTENT is valid JSON."
        else
            echo "❌ OPENCODE_CONFIG_CONTENT has invalid JSON."
        fi
        rm -f "$tmp"
    fi
}

# ─── Load Account ─────────────────────────────────────────────────────────────

load_account() {
    local name="$1"
    local file="$OPENCODE_ACCOUNTS_DIR/$name.env"

    if [ ! -f "$file" ]; then
        echo "❌ Error: Account '$name' not found at $file"
        echo ""
        echo "Available accounts:"
        list_accounts
        exit 1
    fi

    # Source the env file
    set -a
    # shellcheck disable=SC1090
    source "$file"
    set +a

    echo "✅ Loaded account: $name"

    # Show active providers
    local active_providers=()
    for var in "${OPENCODE_PROVIDER_VARS[@]}"; do
        local val="${!var:-}"
        if [ -n "$val" ] && _is_provider_var "$var"; then
            case "$var" in
                ANTHROPIC_API_KEY) active_providers+=("anthropic") ;;
                OPENAI_API_KEY) active_providers+=("openai") ;;
                GEMINI_API_KEY) active_providers+=("gemini") ;;
                GROQ_API_KEY) active_providers+=("groq") ;;
                OPENROUTER_API_KEY) active_providers+=("openrouter") ;;
                XAI_API_KEY) active_providers+=("xai") ;;
                AZURE_OPENAI_API_KEY) active_providers+=("azure") ;;
                AWS_ACCESS_KEY_ID) active_providers+=("bedrock") ;;
            esac
        fi
    done

    if [ ${#active_providers[@]} -gt 0 ]; then
        echo "  Providers: $(IFS=','; echo "${active_providers[*]}")"
    fi

    if [ -n "${OPENCODE_DEFAULT_PROVIDER:-}" ] && [ -n "${OPENCODE_DEFAULT_MODEL:-}" ]; then
        echo "  Default: ${OPENCODE_DEFAULT_PROVIDER}/${OPENCODE_DEFAULT_MODEL}"
    elif [ -n "${OPENCODE_DEFAULT_MODEL:-}" ]; then
        echo "  Model: ${OPENCODE_DEFAULT_MODEL}"
    fi

    if [ -n "${OPENCODE_CONFIG_CONTENT:-}" ]; then
        echo "  ⚙ Config override: active"
    fi

    echo ""
    echo "Environment variables exported to current shell."
    echo "Run 'opencode' to start with this account."
}

# ─── Run With Account ─────────────────────────────────────────────────────────

run_with_account() {
    local name="$1"
    shift

    local file="$OPENCODE_ACCOUNTS_DIR/$name.env"

    if [ ! -f "$file" ]; then
        echo "❌ Error: Account '$name' not found at $file"
        exit 1
    fi

    # Run command with sourced environment in subshell
    (
        set -a
        # shellcheck disable=SC1090
        source "$file"
        set +a

        if [ $# -eq 0 ]; then
            echo "❌ Error: No command specified."
            echo "Usage: opencode-env.sh $name <command> [args...]"
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
        if [ -f "$OPENCODE_ACCOUNTS_DIR/$1.env" ]; then
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
