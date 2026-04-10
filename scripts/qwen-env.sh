#!/usr/bin/env bash
# qwen-env.sh - Environment-based account switcher for Qwen Code CLI
#
# Manages multiple Qwen Code accounts using .env files.
# Qwen Code natively supports .env loading and modelProviders with envKey mapping.
#
# Usage:
#   qwen-env.sh list                        List all accounts
#   qwen-env.sh create <name>               Create new account config
#   qwen-env.sh show <name>                 Show account details (keys masked)
#   qwen-env.sh edit <name>                 Edit account in $EDITOR
#   qwen-env.sh validate <name>             Validate config syntax
#   qwen-env.sh <name>                      Export vars to current shell
#   qwen-env.sh <name> qwen [args...]       Run qwen with account
#
# OAuth Account Commands (for switching between Qwen accounts):
#   qwen-env.sh oauth-list                  List stored OAuth accounts
#   qwen-env.sh oauth-create <name>         Save current OAuth creds as account
#   qwen-env.sh oauth-switch <name>         Switch to stored OAuth account
#   qwen-env.sh oauth-current               Show current OAuth account info
#   qwen-env.sh oauth-delete <name>        Delete stored OAuth account
#   qwen-env.sh oauth-login                 Clear creds and trigger new login
#
# Shell Aliases (add to ~/.zshrc):
#   alias qe='qwen-env.sh'
#   alias qeol='qwen-env.sh oauth-list'
#   alias qeoc='qwen-env.sh oauth-create'
#   alias qeos='qwen-env.sh oauth-switch'
#   alias qeocurrent='qwen-env.sh oauth-current'
#
# Examples:
#   qwen-env.sh create work
#   qwen-env.sh create personal
#   qwen-env.sh oauth-create account1      # Save current Qwen login
#   qwen-env.sh oauth-create account2      # Log in with different account, save
#   qwen-env.sh oauth-switch account2       # Switch to account2
#   qwen                                    # Run with switched account

set -euo pipefail

QWEN_ACCOUNTS_DIR="${QWEN_ACCOUNTS_DIR:-${HOME}/.config/qwen/accounts}"
QWEN_OAUTH_DIR="${QWEN_OAUTH_DIR:-${HOME}/.config/qwen/oauth-accounts}"

# OAuth account storage
_qwen_oauth_dir() {
    echo "$QWEN_OAUTH_DIR"
}

_qwen_current_oauth() {
    local current="${HOME}/.qwen/oauth_creds.json"
    if [ -f "$current" ]; then
        _hash_file "$current"
    fi
}

_hash_file() {
    local file="$1"
    if [ -f "$file" ]; then
        shasum -a 256 "$file" 2>/dev/null | cut -d' ' -f1 || \
        sha256sum "$file" 2>/dev/null | cut -d' ' -f1 || \
        echo "unknown"
    else
        echo "none"
    fi
}

# ─── Known Qwen Code environment variables ────────────────────────────────────

QWEN_PROVIDER_VARS=(
    "OPENAI_API_KEY"
    "ANTHROPIC_API_KEY"
    "GEMINI_API_KEY"
    "BAILIAN_CODING_PLAN_API_KEY"
    "DASHSCOPE_API_KEY"
    "QWEN_API_KEY"
    "OPENAI_BASE_URL"
    "ANTHROPIC_BASE_URL"
    "QWEN_MODEL"
    "QWEN_REGION"
)

QWEN_SECRET_VARS=(
    "OPENAI_API_KEY"
    "ANTHROPIC_API_KEY"
    "GEMINI_API_KEY"
    "BAILIAN_CODING_PLAN_API_KEY"
    "DASHSCOPE_API_KEY"
    "QWEN_API_KEY"
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

_validate_env_file() {
    local file=$1
    local line_num=0
    local errors=0

    while IFS= read -r line || [ -n "$line" ]; do
        line_num=$((line_num + 1))
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        if [[ ! "$line" =~ ^[A-Za-z_]+= ]]; then
            echo "  ⚠ Line $line_num: Invalid format: ${line:0:50}"
            errors=$((errors + 1))
        fi
    done < "$file"

    return $errors
}

_validate_json() {
    local file=$1
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
    for known in "${QWEN_SECRET_VARS[@]}"; do
        [ "$var" = "$known" ] && return 0
    done
    return 1
}

# ─── OAuth Account Management ─────────────────────────────────────────────────

_qwen_oauth_ensure_dir() {
    local dir=$(_qwen_oauth_dir)
    if [ ! -d "$dir" ]; then
        mkdir -p "$dir"
    fi
}

_qwen_oauth_list() {
    local dir=$(_qwen_oauth_dir)
    if [ ! -d "$dir" ] || [ -z "$(ls -A "$dir" 2>/dev/null)" ]; then
        echo "No OAuth accounts stored."
        echo "Create one with: qwen-env.sh oauth-create <name>"
        return
    fi

    local current_hash
    current_hash=$(_qwen_current_oauth)

    echo "OAuth accounts (linked to ~/.qwen/oauth_creds.json):"
    echo ""

    local has_accounts=false
    for account_dir in "$dir"/*/; do
        [ -d "$account_dir" ] || continue
        has_accounts=true
        local name
        name=$(basename "$account_dir")
        local creds_file="${account_dir}oauth_creds.json"
        
        local marker=""
        if [ -f "$creds_file" ]; then
            local account_hash
            account_hash=$(_hash_file "$creds_file")
            if [ "$account_hash" = "$current_hash" ]; then
                marker=" ✓ (active)"
            fi
        fi

        local email="unknown"
        if [ -f "$creds_file" ]; then
            if command -v python3 &>/dev/null; then
                email=$(python3 -c "import json, sys; d=json.load(open(sys.argv[1])); print(d.get('email','unknown'))" "$creds_file" 2>/dev/null || echo "unknown")
            elif command -v jq &>/dev/null; then
                email=$(jq -r '.email // "unknown"' "$creds_file" 2>/dev/null || echo "unknown")
            fi
        fi

        echo "  • ${name}${marker}  ($email)"
    done

    if [ "$has_accounts" = false ]; then
        echo "No OAuth accounts stored."
    fi

    echo ""
    echo "OAuth accounts directory: $dir"
}

_qwen_oauth_create() {
    local name="${1:-}"

    if [ -z "$name" ]; then
        echo "❌ Error: Account name required."
        echo "Usage: qwen-env.sh oauth-create <name>"
        exit 1
    fi

    if [[ ! "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo "❌ Error: Account name can only contain letters, numbers, hyphens, and underscores."
        exit 1
    fi

    _qwen_oauth_ensure_dir

    local target_dir=$(_qwen_oauth_dir)/$name
    local current_creds="${HOME}/.qwen/oauth_creds.json"
    local backup_creds="${HOME}/.qwen/oauth_creds.json.bak"

    if [ -d "$target_dir" ]; then
        echo "❌ Error: OAuth account '$name' already exists."
        echo "Switch to it with: qwen-env.sh oauth-switch $name"
        exit 1
    fi

    mkdir -p "$target_dir"

    if [ -f "$current_creds" ]; then
        cp "$current_creds" "$target_dir/oauth_creds.json"
        echo "✅ Created OAuth account: $name"
        echo "Saved current OAuth credentials to: $target_dir/oauth_creds.json"
    else
        echo "✅ Created OAuth account: $name"
        echo "⚠ No current OAuth credentials found."
        echo "Run 'qwen' first to log in, then run: qwen-env.sh oauth-save"
    fi
    echo ""
    echo "To switch to this account: qwen-env.sh oauth-switch $name"
}

_qwen_oauth_switch() {
    local name="${1:-}"

    if [ -z "$name" ]; then
        echo "❌ Error: Account name required."
        echo "Usage: qwen-env.sh oauth-switch <name>"
        exit 1
    fi

    local source_dir=$(_qwen_oauth_dir)/$name
    local source_creds="$source_dir/oauth_creds.json"
    local target_creds="${HOME}/.qwen/oauth_creds.json"

    if [ ! -d "$source_dir" ]; then
        echo "❌ Error: OAuth account '$name' not found."
        echo "Available accounts:"
        _qwen_oauth_list
        exit 1
    fi

    if [ ! -f "$source_creds" ]; then
        echo "❌ Error: No oauth_creds.json found for account '$name'."
        exit 1
    fi

    # Backup current before switching
    if [ -f "$target_creds" ]; then
        cp "$target_creds" "${target_creds}.bak"
    fi

    if [ "${DRY_RUN:-}" = "1" ]; then
        echo "DRY RUN: Would copy $source_creds to $target_creds"
    else
        cp "$source_creds" "$target_creds"
        echo "✅ Switched to OAuth account: $name"
    fi

    echo ""
    echo "Now run 'qwen' to use this account."
}

_qwen_oauth_current() {
    local current="${HOME}/.qwen/oauth_creds.json"
    
    if [ ! -f "$current" ]; then
        echo "No active OAuth account (no oauth_creds.json found)."
        return
    fi

    echo "Current OAuth account:"
    echo "  File: $current"
    
    local email="unknown"
    if command -v python3 &>/dev/null; then
        email=$(python3 -c "import json, sys; d=json.load(open(sys.argv[1])); print(d.get('email','unknown'))" "$current" 2>/dev/null || echo "unknown")
    elif command -v jq &>/dev/null; then
        email=$(jq -r '.email // "unknown"' "$current" 2>/dev/null || echo "unknown")
    fi
    echo "  Email: $email"

    # Check if it matches any stored account
    local dir=$(_qwen_oauth_dir)
    local current_hash
    current_hash=$(_hash_file "$current")
    
    for account_dir in "$dir"/*/; do
        [ -d "$account_dir" ] || continue
        local account_name
        account_name=$(basename "$account_dir")
        local account_creds="${account_dir}oauth_creds.json"
        
        if [ -f "$account_creds" ]; then
            local account_hash
            account_hash=$(_hash_file "$account_creds")
            if [ "$account_hash" = "$current_hash" ]; then
                echo "  Stored as: $account_name"
                return
            fi
        fi
    done
    
    echo "  Stored as: (not stored - run 'qwen-env.sh oauth-save' to save)"
}

_qwen_oauth_delete() {
    local name="${1:-}"

    if [ -z "$name" ]; then
        echo "❌ Error: Account name required."
        echo "Usage: qwen-env.sh oauth-delete <name>"
        exit 1
    fi

    local target_dir=$(_qwen_oauth_dir)/$name

    if [ ! -d "$target_dir" ]; then
        echo "❌ Error: OAuth account '$name' not found."
        exit 1
    fi

    if [ "${DRY_RUN:-}" = "1" ]; then
        echo "DRY RUN: Would delete $target_dir"
    else
        rm -rf "$target_dir"
        echo "✅ Deleted OAuth account: $name"
    fi
}

_qwen_oauth_save() {
    local name="${1:-}"

    if [ -z "$name" ]; then
        echo "❌ Error: Account name required."
        echo "Usage: qwen-env.sh oauth-save <name>"
        exit 1
    fi

    if [[ ! "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo "❌ Error: Account name can only contain letters, numbers, hyphens, and underscores."
        exit 1
    fi

    local current="${HOME}/.qwen/oauth_creds.json"
    
    if [ ! -f "$current" ]; then
        echo "❌ Error: No oauth_creds.json found."
        echo "Run 'qwen' to log in first."
        exit 1
    fi

    _qwen_oauth_ensure_dir

    local target_dir=$(_qwen_oauth_dir)/$name
    
    if [ -d "$target_dir" ]; then
        echo "⚠ Account '$name' already exists. Updating..."
    else
        mkdir -p "$target_dir"
    fi

    cp "$current" "$target_dir/oauth_creds.json"
    echo "✅ Saved current OAuth credentials as: $name"
}

# ─── Usage ────────────────────────────────────────────────────────────────────

usage() {
    cat << 'USAGE'
Qwen Code CLI Account Manager (Environment-based)

Usage: qwen-env.sh <command> [arguments]

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
  qwen-env.sh create work
  qwen-env.sh work                        # Export vars for current shell
  qwen-env.sh work qwen                   # Run qwen with work account
  qwen-env.sh edit work                   # Edit in $EDITOR
  qwen-env.sh validate work               # Check config syntax
  DRY_RUN=1 qwen-env.sh work qwen         # Preview without running

Environment Variables (supported in account files):
  OPENAI_API_KEY              OpenAI provider key
  ANTHROPIC_API_KEY           Anthropic provider key
  GEMINI_API_KEY              Google Gemini key
  BAILIAN_CODING_PLAN_API_KEY Alibaba Cloud Coding Plan key
  DASHSCOPE_API_KEY           DashScope (Tongyi Qianwen) key
  QWEN_API_KEY                Qwen direct key
  OPENAI_BASE_URL             Custom OpenAI-compatible endpoint
  ANTHROPIC_BASE_URL          Custom Anthropic endpoint
  QWEN_MODEL                  Default model override
  QWEN_REGION                 Region for cloud services
  EDITOR                      Preferred editor (default: nano)

Qwen Code Configuration:
  User settings:  ~/.qwen/settings.json  (modelProviders definition)
  Key storage:    ~/.qwen/.env           (API keys)
  OAuth creds:    ~/.qwen/oauth_creds.json

OAuth Commands (for switching between Qwen accounts):
  qwen-env.sh oauth-list                  List stored OAuth accounts
  qwen-env.sh oauth-create <name>         Save current OAuth creds as account
  qwen-env.sh oauth-switch <name>         Switch to stored OAuth account
  qwen-env.sh oauth-save <name>           Save current OAuth creds (alias for oauth-create)
  qwen-env.sh oauth-current               Show current OAuth account info
  qwen-env.sh oauth-delete <name>         Delete stored OAuth account
  qwen-env.sh oauth-login                 Clear creds and trigger new login

Examples:
  qwen-env.sh oauth-create work          # Save current logged-in account
  qwen-env.sh oauth-create personal       # Save another account
  qwen-env.sh oauth-switch work           # Switch to work account
  qwen                                    # Run with switched account
USAGE
    exit 0
}

# ─── List Accounts ────────────────────────────────────────────────────────────

list_accounts() {
    if [ ! -d "$QWEN_ACCOUNTS_DIR" ]; then
        echo "No accounts found."
        echo "Create one with: qwen-env.sh create <name>"
        return
    fi

    local has_accounts=false
    echo "Available accounts:"
    echo ""

    # Compute combined hash of current shell's secret vars
    local current_hash=""
    local combined=""
    for var in "${QWEN_SECRET_VARS[@]}"; do
        local val="${!var:-}"
        if [ -n "$val" ]; then
            combined="${combined}${var}=${val}:"
        fi
    done
    if [ -n "$combined" ]; then
        current_hash=$(_hash_string "$combined")
    fi

    shopt -s nullglob 2>/dev/null || true
    local files=("$QWEN_ACCOUNTS_DIR"/*.env)
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
            for var in "${QWEN_SECRET_VARS[@]}"; do
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

        # Show configured providers
        local providers=()
        for var in "${QWEN_PROVIDER_VARS[@]}"; do
            local val
            val=$(grep -E "^${var}=" "$file" 2>/dev/null | head -1 | cut -d'=' -f2- || echo "")
            if [ -n "$val" ]; then
                case "$var" in
                    OPENAI_API_KEY) providers+=("openai") ;;
                    ANTHROPIC_API_KEY) providers+=("anthropic") ;;
                    GEMINI_API_KEY) providers+=("gemini") ;;
                    BAILIAN_CODING_PLAN_API_KEY|DASHSCOPE_API_KEY) providers+=("dashscope") ;;
                    QWEN_API_KEY) providers+=("qwen") ;;
                esac
            fi
        done

        local model
        model=$(grep -E '^QWEN_MODEL=' "$file" 2>/dev/null | head -1 | cut -d'=' -f2- || echo "")

        local info=""
        if [ ${#providers[@]} -gt 0 ]; then
            info=$(IFS=','; echo "${providers[*]}")
        fi
        [ -n "$model" ] && info="$info → $model"

        if [ -n "$info" ]; then
            echo "  • ${name}${marker}  ($info)"
        else
            echo "  • ${name}${marker}"
        fi
    done

    if [ "$has_accounts" = false ]; then
        echo "No accounts found."
        echo "Create one with: qwen-env.sh create <name>"
    fi

    echo ""
    echo "Accounts directory: $QWEN_ACCOUNTS_DIR"
}

# ─── Create Account ───────────────────────────────────────────────────────────

create_account() {
    local name="${1:-}"

    if [ -z "$name" ]; then
        echo "❌ Error: Account name required."
        echo "Usage: qwen-env.sh create <name>"
        exit 1
    fi

    if [[ ! "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo "❌ Error: Account name can only contain letters, numbers, hyphens, and underscores."
        exit 1
    fi

    mkdir -p "$QWEN_ACCOUNTS_DIR"

    local file="$QWEN_ACCOUNTS_DIR/$name.env"

    if [ -f "$file" ]; then
        echo "❌ Error: Account '$name' already exists."
        echo "Edit it with: qwen-env.sh edit $name"
        exit 1
    fi

    cat > "$file" << 'EOF'
# Qwen Code Account Configuration
# Set API keys for the providers you want to use.
# Qwen Code reads these via .env file loading.

# ─── Provider API Keys ───────────────────────────────────────────
# OpenAI (GPT models)
# OPENAI_API_KEY=sk-proj-your-key-here

# Anthropic (Claude models)
# ANTHROPIC_API_KEY=sk-ant-your-key-here

# Google Gemini
# GEMINI_API_KEY=ai-your-key-here

# Alibaba Cloud / DashScope (Tongyi Qianwen / Qwen models)
# BAILIAN_CODING_PLAN_API_KEY=sk-your-bailian-key
# DASHSCOPE_API_KEY=sk-your-dashscope-key

# Qwen direct (if using qwen-api)
# QWEN_API_KEY=sk-qwen-your-key-here

# ─── Custom Endpoints (optional) ─────────────────────────────────
# OPENAI_BASE_URL=https://your-openai-compatible-api/v1
# ANTHROPIC_BASE_URL=https://your-anthropic-proxy/v1

# ─── Default Model Override ──────────────────────────────────────
# QWEN_MODEL=qwen-coder-plus-latest
# QWEN_REGION=cn-shanghai
EOF

    chmod 600 "$file"

    echo "✅ Created account: $name"
    echo "Config file: $file"
    echo ""
    echo "Next steps:"
    echo "  1. Edit the file: qwen-env.sh edit $name"
    echo "  2. Uncomment and set your API keys"
    echo "  3. Activate: qwen-env.sh $name"
    echo "  4. Run: qwen"
    echo ""
    echo "Or run directly: qwen-env.sh $name qwen"
}

# ─── Show Account ─────────────────────────────────────────────────────────────

show_account() {
    local name="${1:-}"
    local file="$QWEN_ACCOUNTS_DIR/$name.env"

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

    local model region base_urls
    model=$(grep -E '^QWEN_MODEL=' "$file" 2>/dev/null | head -1 | cut -d'=' -f2- || echo "")
    region=$(grep -E '^QWEN_REGION=' "$file" 2>/dev/null | head -1 | cut -d'=' -f2- || echo "")
    [ -n "$model" ] && echo "  Default Model: $model"
    [ -n "$region" ] && echo "  Region: $region"

    echo ""
    echo "Configured credentials:"

    local has_creds=false
    for var in "${QWEN_PROVIDER_VARS[@]}"; do
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
    local file="$QWEN_ACCOUNTS_DIR/$name.env"

    if [ ! -f "$file" ]; then
        echo "❌ Error: Account '$name' not found."
        echo "Create it with: qwen-env.sh create $name"
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
    local file="$QWEN_ACCOUNTS_DIR/$name.env"

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

    # Also check ~/.qwen/settings.json if it exists
    local qwen_settings="${HOME}/.qwen/settings.json"
    if [ -f "$qwen_settings" ]; then
        echo ""
        echo "Checking ~/.qwen/settings.json..."
        if _validate_json "$qwen_settings"; then
            echo "✅ settings.json is valid."
        else
            echo "❌ settings.json has invalid JSON."
        fi
    fi
}

# ─── Load Account ─────────────────────────────────────────────────────────────

load_account() {
    local name="$1"
    local file="$QWEN_ACCOUNTS_DIR/$name.env"

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

    # Show active providers
    local active_providers=()
    for var in "${QWEN_SECRET_VARS[@]}"; do
        local val="${!var:-}"
        if [ -n "$val" ]; then
            case "$var" in
                OPENAI_API_KEY) active_providers+=("openai") ;;
                ANTHROPIC_API_KEY) active_providers+=("anthropic") ;;
                GEMINI_API_KEY) active_providers+=("gemini") ;;
                BAILIAN_CODING_PLAN_API_KEY) active_providers+=("bailian") ;;
                DASHSCOPE_API_KEY) active_providers+=("dashscope") ;;
                QWEN_API_KEY) active_providers+=("qwen") ;;
            esac
        fi
    done

    if [ ${#active_providers[@]} -gt 0 ]; then
        echo "  Providers: $(IFS=','; echo "${active_providers[*]}")"
    fi

    if [ -n "${QWEN_MODEL:-}" ]; then
        echo "  Model: ${QWEN_MODEL}"
    fi

    echo ""
    echo "Environment variables exported to current shell."
    echo "Run 'qwen' to start with this account."
}

# ─── Run With Account ─────────────────────────────────────────────────────────

run_with_account() {
    local name="$1"
    shift

    local file="$QWEN_ACCOUNTS_DIR/$name.env"

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
            echo "Usage: qwen-env.sh $name <command> [args...]"
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
    # OAuth commands
    oauth-list)
        _qwen_oauth_list
        ;;
    oauth-create)
        _qwen_oauth_create "${2:-}"
        ;;
    oauth-switch)
        _qwen_oauth_switch "${2:-}"
        ;;
    oauth-save)
        _qwen_oauth_save "${2:-}"
        ;;
    oauth-current)
        _qwen_oauth_current
        ;;
    oauth-delete)
        _qwen_oauth_delete "${2:-}"
        ;;
    oauth-login)
        rm -f "${HOME}/.qwen/oauth_creds.json"
        echo "✅ Cleared OAuth credentials."
        echo "Run 'qwen' to log in with a different account."
        ;;
    ""|--help|-h|help)
        usage
        ;;
    *)
        if [ -f "$QWEN_ACCOUNTS_DIR/$1.env" ]; then
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
