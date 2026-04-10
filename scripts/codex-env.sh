#!/usr/bin/env bash
# codex-env.sh - Environment-based account switcher for OpenAI Codex CLI
#
# Manages multiple Codex accounts using environment variable files.
# Each account stores credentials and config overrides.
#
# Usage:
#   codex-env.sh list                        List all accounts
#   codex-env.sh create <name>               Create new account config
#   codex-env.sh show <name>                 Show account details (keys masked)
#   codex-env.sh edit <name>                 Edit account in $EDITOR
#   codex-env.sh validate <name>             Validate config syntax
#   codex-env.sh <name>                      Export vars to current shell
#   codex-env.sh <name> codex [args...]      Run codex with account
#
# Examples:
#   codex-env.sh create work
#   codex-env.sh create personal
#   codex-env.sh work                        # Export vars
#   codex-env.sh work codex                  # Run codex with work account

set -euo pipefail

CODEX_ACCOUNTS_DIR="${CODEX_ACCOUNTS_DIR:-${HOME}/.config/codex/accounts}"
CODEX_HOME="${CODEX_HOME:-${HOME}/.codex}"
CODEX_CONFIG="${CODEX_HOME}/config.toml"

CODEX_PROVIDER_VARS=(
    "OPENAI_API_KEY"
    "ANTHROPIC_API_KEY"
    "GOOGLE_API_KEY"
    "GEMINI_API_KEY"
    "AZURE_OPENAI_API_KEY"
    "AZURE_OPENAI_ENDPOINT"
    "AWS_ACCESS_KEY_ID"
    "AWS_SECRET_ACCESS_KEY"
    "AWS_REGION"
    "OLLAMA_API_KEY"
    "XAI_API_KEY"
    "GITHUB_TOKEN"
)

_hash_string() {
    printf '%s' "$1" | shasum -a 256 2>/dev/null | cut -d' ' -f1 || \
    printf '%s' "$1" | sha256sum 2>/dev/null | cut -d' ' -f1 || \
    echo "unknown"
}

_get_editor() {
    echo "${EDITOR:-${VISUAL:-nano}}"
}

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

_is_provider_var() {
    local var="$1"
    for known in "${CODEX_PROVIDER_VARS[@]}"; do
        [ "$var" = "$known" ] && return 0
    done
    return 1
}

usage() {
    cat << 'USAGE'
OpenAI Codex CLI Account Manager

Usage: codex-env.sh <command> [arguments]

Commands:
  list                  List available accounts
  create <name>         Create new account config
  show <name>           Show account configuration (keys masked)
  edit <name>           Edit account config in $EDITOR
  validate <name>       Validate account config syntax
  <name>                Export account env vars to current shell
  <name> <command>      Run command with account credentials

Accounts directory: ~/.config/codex/accounts

Examples:
  codex-env.sh create work
  codex-env.sh work                      # Export vars for current shell
  codex-env.sh work codex                # Run codex with work account
  codex-env.sh edit work                 # Edit in $EDITOR

Environment Variables:
  OPENAI_API_KEY         OpenAI API key
  ANTHROPIC_API_KEY      Anthropic API key (for custom providers)
  GOOGLE_API_KEY         Google API key
  AZURE_OPENAI_*         Azure OpenAI endpoint + key
  AWS_ACCESS_KEY_ID      AWS credentials for Bedrock
  OLLAMA_API_KEY         Ollama API key
  XAI_API_KEY            xAI (Grok) key
  GITHUB_TOKEN           GitHub token for MCP
  CODEX_MODEL            Default model (e.g., gpt-5.4)
  CODEX_PROVIDER         Provider to use (openai, azure, etc.)
USAGE
    exit 0
}

list_accounts() {
    if [ ! -d "$CODEX_ACCOUNTS_DIR" ]; then
        echo "No accounts found."
        echo "Create one with: codex-env.sh create <name>"
        return
    fi

    local has_accounts=false
    echo "Available accounts:"
    echo ""

    local current_hash=""
    local combined=""
    for var in "${CODEX_PROVIDER_VARS[@]}"; do
        local val="${!var:-}"
        if [ -n "$val" ]; then
            combined="${combined}${var}=${val}:"
        fi
    done
    if [ -n "$combined" ]; then
        current_hash=$(_hash_string "$combined")
    fi

    shopt -s nullglob 2>/dev/null || true
    local files=("$CODEX_ACCOUNTS_DIR"/*.env)
    shopt -u nullglob 2>/dev/null || true

    for file in "${files[@]}"; do
        [ -f "$file" ] || continue
        has_accounts=true
        local name
        name=$(basename "$file" .env)

        local marker=""
        if [ -n "$current_hash" ]; then
            local file_combined=""
            for var in "${CODEX_PROVIDER_VARS[@]}"; do
                local file_val
                file_val=$(grep -E "^${var}=" "$file" 2>/dev/null | head -1 | cut -d'=' -f2- || echo "")
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

        local providers=()
        for var in "${CODEX_PROVIDER_VARS[@]}"; do
            local val
            val=$(grep -E "^${var}=" "$file" 2>/dev/null | head -1 | cut -d'=' -f2- || echo "")
            if [ -n "$val" ]; then
                case "$var" in
                    OPENAI_API_KEY) providers+=("openai") ;;
                    ANTHROPIC_API_KEY) providers+=("anthropic") ;;
                    GOOGLE_API_KEY|GEMINI_API_KEY) providers+=("gemini") ;;
                    AZURE_OPENAI_API_KEY) providers+=("azure") ;;
                    AWS_ACCESS_KEY_ID) providers+=("bedrock") ;;
                    OLLAMA_API_KEY) providers+=("ollama") ;;
                    XAI_API_KEY) providers+=("xai") ;;
                esac
            fi
        done

        local model provider
        model=$(grep -E "^CODEX_MODEL=" "$file" 2>/dev/null | head -1 | cut -d'=' -f2- || echo "")
        provider=$(grep -E "^CODEX_PROVIDER=" "$file" 2>/dev/null | head -1 | cut -d'=' -f2- || echo "")

        local info=""
        if [ ${#providers[@]} -gt 0 ]; then
            info=$(IFS=','; echo "${providers[*]}")
        fi
        if [ -n "$provider" ] && [ -n "$model" ]; then
            info="$info → $provider/$model"
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
        echo "Create one with: codex-env.sh create <name>"
    fi

    echo ""
    echo "Accounts directory: $CODEX_ACCOUNTS_DIR"
}

create_account() {
    local name="${1:-}"

    if [ -z "$name" ]; then
        echo "❌ Error: Account name required."
        echo "Usage: codex-env.sh create <name>"
        exit 1
    fi

    if [[ ! "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo "❌ Error: Account name can only contain letters, numbers, hyphens, and underscores."
        exit 1
    fi

    mkdir -p "$CODEX_ACCOUNTS_DIR"

    local file="$CODEX_ACCOUNTS_DIR/$name.env"

    if [ -f "$file" ]; then
        echo "❌ Error: Account '$name' already exists."
        echo "Edit it with: codex-env.sh edit $name"
        exit 1
    fi

    cat > "$file" << 'EOF'
# Codex CLI Account Configuration
# Fill in credentials for the providers you use.

# ─── OpenAI ───────────────────────────────────────────────────────
# OPENAI_API_KEY=sk-proj-your-key-here

# ─── Alternative Providers ───────────────────────────────────────
# ANTHROPIC_API_KEY=sk-ant-your-key-here
# GOOGLE_API_KEY=your-google-key
# GEMINI_API_KEY=your-gemini-key

# ─── Azure OpenAI ───────────────────────────────────────────────
# AZURE_OPENAI_ENDPOINT=https://your-resource.openai.azure.com
# AZURE_OPENAI_API_KEY=your-azure-key

# ─── AWS Bedrock ─────────────────────────────────────────────────
# AWS_ACCESS_KEY_ID=AKIA...
# AWS_SECRET_ACCESS_KEY=...
# AWS_REGION=us-east-1

# ─── Local Models ───────────────────────────────────────────────
# OLLAMA_API_KEY=your-ollama-key

# ─── xAI ──────────────────────────────────────────────────────────
# XAI_API_KEY=your-xai-key

# ─── GitHub (for MCP) ────────────────────────────────────────────
# GITHUB_TOKEN=ghp_your-token

# ─── Configuration ────────────────────────────────────────────────
# CODEX_MODEL=gpt-5.4
# CODEX_PROVIDER=openai
# CODEX_APPROVAL_MODE=full-auto

# ─── Custom Config (advanced) ────────────────────────────────────
# Override config.toml settings:
# CODEX_CONFIG_OVERRIDE='model = "gpt-5.4"'
EOF

    chmod 600 "$file"

    echo "✅ Created account: $name"
    echo "Config file: $file"
    echo ""
    echo "Next steps:"
    echo "  1. Edit the file: codex-env.sh edit $name"
    echo "  2. Uncomment and set your API keys"
    echo "  3. Activate: codex-env.sh $name"
    echo "  4. Run: codex"
    echo ""
    echo "Or run directly: codex-env.sh $name codex"
}

show_account() {
    local name="${1:-}"
    local file="$CODEX_ACCOUNTS_DIR/$name.env"

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

    local def_provider def_model
    def_provider=$(grep -E '^CODEX_PROVIDER=' "$file" 2>/dev/null | head -1 | cut -d'=' -f2- || echo "")
    def_model=$(grep -E '^CODEX_MODEL=' "$file" 2>/dev/null | head -1 | cut -d'=' -f2- || echo "")
    [ -n "$def_provider" ] && echo "  Default Provider: $def_provider"
    [ -n "$def_model" ] && echo "  Default Model: $def_model"

    echo ""
    echo "Configured credentials:"

    local has_creds=false
    for var in "${CODEX_PROVIDER_VARS[@]}"; do
        local file_val
        file_val=$(grep -E "^${var}=" "$file" 2>/dev/null | head -1 | cut -d'=' -f2- || echo "")
        if [ -n "$file_val" ]; then
            has_creds=true
            local friendly_name="$var"
            case "$var" in
                OPENAI_API_KEY) friendly_name="OpenAI" ;;
                ANTHROPIC_API_KEY) friendly_name="Anthropic" ;;
                GOOGLE_API_KEY) friendly_name="Google" ;;
                GEMINI_API_KEY) friendly_name="Gemini" ;;
                AZURE_OPENAI_ENDPOINT) friendly_name="Azure Endpoint" ;;
                AZURE_OPENAI_API_KEY) friendly_name="Azure Key" ;;
                AWS_ACCESS_KEY_ID) friendly_name="AWS Access Key" ;;
                AWS_SECRET_ACCESS_KEY) friendly_name="AWS Secret Key" ;;
                AWS_REGION) friendly_name="AWS Region" ;;
                OLLAMA_API_KEY) friendly_name="Ollama" ;;
                XAI_API_KEY) friendly_name="xAI (Grok)" ;;
                GITHUB_TOKEN) friendly_name="GitHub Token" ;;
            esac
            echo "  $friendly_name: $(_mask_value "$file_val")"
        fi
    done

    [ "$has_creds" = false ] && echo "  (no credentials configured)"
    echo "---"

    if ! _validate_env_file "$file" 2>/dev/null; then
        echo "⚠ Config has syntax warnings"
    fi
}

edit_account() {
    local name="${1:-}"
    local file="$CODEX_ACCOUNTS_DIR/$name.env"

    if [ ! -f "$file" ]; then
        echo "❌ Error: Account '$name' not found."
        echo "Create it with: codex-env.sh create $name"
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
        echo "⚠ Config saved but has syntax warnings."
    fi
}

validate_account() {
    local name="${1:-}"
    local file="$CODEX_ACCOUNTS_DIR/$name.env"

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
        echo "❌ Config has syntax errors."
        exit 1
    fi
}

load_account() {
    local name="$1"
    local file="$CODEX_ACCOUNTS_DIR/$name.env"

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

    local active_providers=()
    for var in "${CODEX_PROVIDER_VARS[@]}"; do
        local val="${!var:-}"
        if [ -n "$val" ] && _is_provider_var "$var"; then
            case "$var" in
                OPENAI_API_KEY) active_providers+=("openai") ;;
                ANTHROPIC_API_KEY) active_providers+=("anthropic") ;;
                GOOGLE_API_KEY|GEMINI_API_KEY) active_providers+=("gemini") ;;
                AZURE_OPENAI_API_KEY) active_providers+=("azure") ;;
                AWS_ACCESS_KEY_ID) active_providers+=("bedrock") ;;
                OLLAMA_API_KEY) active_providers+=("ollama") ;;
                XAI_API_KEY) active_providers+=("xai") ;;
            esac
        fi
    done

    if [ ${#active_providers[@]} -gt 0 ]; then
        echo "  Providers: $(IFS=','; echo "${active_providers[*]}")"
    fi

    if [ -n "${CODEX_PROVIDER:-}" ] && [ -n "${CODEX_MODEL:-}" ]; then
        echo "  Default: ${CODEX_PROVIDER}/${CODEX_MODEL}"
    elif [ -n "${CODEX_MODEL:-}" ]; then
        echo "  Model: ${CODEX_MODEL}"
    fi

    echo ""
    echo "Environment variables exported to current shell."
    echo "Run 'codex' to start with this account."
}

run_with_account() {
    local name="$1"
    shift

    local file="$CODEX_ACCOUNTS_DIR/$name.env"

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
            echo "Usage: codex-env.sh $name <command> [args...]"
            exit 1
        fi

        exec "$@"
    )
}

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
        if [ -f "$CODEX_ACCOUNTS_DIR/$1.env" ]; then
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
