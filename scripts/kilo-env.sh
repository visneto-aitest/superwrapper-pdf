#!/usr/bin/env bash
# kilo-env.sh - Environment-based account switcher for Kilo CLI
#
# Manages multiple Kilo CLI accounts using environment variable files.
# Each account .env file exports API keys as environment variables.
# Kilo reads these via {env:VAR_NAME} syntax in ~/.config/kilo/kilo.jsonc.
#
# Usage:
#   kilo-env.sh list                  List available accounts
#   kilo-env.sh create <name>         Create new account config
#   kilo-env.sh show <name>           Show account details (keys masked)
#   kilo-env.sh edit <name>           Edit account in $EDITOR
#   kilo-env.sh validate <name>       Validate config syntax
#   kilo-env.sh <name>                Export vars to current shell
#   kilo-env.sh <name> kilo [args...] Run kilo with account
#
# Examples:
#   kilo-env.sh create work
#   kilo-env.sh work                        # Export vars
#   kilo-env.sh work kilo                   # Run kilo with work account

set -euo pipefail

KILO_ACCOUNTS_DIR="${KILO_ACCOUNTS_DIR:-${HOME}/.config/kilo/accounts}"
KILO_AUTH_FILE="${HOME}/.local/share/kilo/auth.json"
KILO_OAUTH_DIR="${KILO_OAUTH_DIR:-${HOME}/.config/kilo/oauth-accounts}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source shared library
if [ -f "$SCRIPT_DIR/lib/common.sh" ]; then
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/lib/common.sh"
else
    # Fallback: define minimal helpers inline
    _get_editor() { printf '%s' "${EDITOR:-${VISUAL:-nano}}"; }
    _hash_string() { printf '%s' "$1" | shasum -a 256 2>/dev/null | cut -d' ' -f1 || printf '%s' "$1" | sha256sum 2>/dev/null | cut -d' ' -f1 || echo "unknown"; }
    _hash_file() { local f="$1"; if [ -f "$f" ]; then shasum -a 256 "$f" 2>/dev/null | cut -d' ' -f1 || sha256sum "$f" 2>/dev/null | cut -d' ' -f1 || echo "unknown"; else echo "none"; fi; }
    _mask_value() { local v="$1" l=${#1}; if [ "$l" -gt 12 ]; then printf '%s' "${v:0:4}****${v: -4} ($l chars)"; elif [ "$l" -gt 0 ]; then printf '%s' "****(masked)"; else printf '%s' "(not set)"; fi; }
    _validate_json() { local f="$1"; if command -v python3 &>/dev/null; then python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$f" 2>/dev/null || return 1; elif command -v jq &>/dev/null; then jq empty "$f" 2>/dev/null || return 1; fi; return 0; }
    _dry_run() { if [ "${DRY_RUN:-0}" = "1" ]; then printf '🔍 [DRY RUN] Would execute: %s\n' "$*"; return 0; else "$@"; fi; }
    _grep_env_key() { local r=""; r=$(grep -E "^${1}=" "$2" 2>/dev/null | head -1 | cut -d'=' -f2-) || r=""; printf '%s' "$r"; }
fi

_kilo_oauth_dir() {
    echo "$KILO_OAUTH_DIR"
}

_kilo_current_oauth() {
    local current="$KILO_AUTH_FILE"
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

_kilo_oauth_ensure_dir() {
    local dir="$(_kilo_oauth_dir)"
    if [ ! -d "$dir" ]; then
        mkdir -p "$dir"
    fi
}

_kilo_oauth_list() {
    local dir="$(_kilo_oauth_dir)"
    if [ ! -d "$dir" ] || [ -z "$(ls -A "$dir" 2>/dev/null)" ]; then
        echo "No OAuth accounts stored."
        echo "Create one with: kilo-env.sh oauth-create <name>"
        return
    fi

    local current_hash
    current_hash=$(_kilo_current_oauth)

    echo "OAuth accounts (linked to $KILO_AUTH_FILE):"
    echo ""

    local has_accounts=false
    for account_dir in "$dir"/*/; do
        [ -d "$account_dir" ] || continue
        has_accounts=true
        local name
        name=$(basename "$account_dir")
        local creds_file="${account_dir}auth.json"
        
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

_kilo_oauth_create() {
    local name="${1:-}"

    if [ -z "$name" ]; then
        echo "❌ Error: Account name required."
        echo "Usage: kilo-env.sh oauth-create <name>"
        exit 1
    fi

    if [[ ! "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo "❌ Error: Account name can only contain letters, numbers, hyphens, and underscores."
        exit 1
    fi

    _kilo_oauth_ensure_dir

    local target_dir="$(_kilo_oauth_dir)/$name"
    local current_creds="$KILO_AUTH_FILE"
    local backup_creds="${KILO_AUTH_FILE}.bak"

    if [ -d "$target_dir" ]; then
        echo "❌ Error: OAuth account '$name' already exists."
        echo "Switch to it with: kilo-env.sh oauth-switch $name"
        exit 1
    fi

    mkdir -p "$target_dir"

    if [ -f "$current_creds" ]; then
        cp "$current_creds" "$target_dir/auth.json"
        echo "✅ Created OAuth account: $name"
        echo "Saved current OAuth credentials to: $target_dir/auth.json"
    else
        echo "✅ Created OAuth account: $name"
        echo "⚠ No current OAuth credentials found."
        echo "Run 'kilo' first to log in, then run: kilo-env.sh oauth-create"
    fi
    echo ""
    echo "To switch to this account: kilo-env.sh oauth-switch $name"
}

_kilo_oauth_switch() {
    local name="${1:-}"

    if [ -z "$name" ]; then
        echo "❌ Error: Account name required."
        echo "Usage: kilo-env.sh oauth-switch <name>"
        exit 1
    fi

    local source_dir="$(_kilo_oauth_dir)/$name"
    local source_creds="$source_dir/auth.json"
    local target_creds="$KILO_AUTH_FILE"

    if [ ! -d "$source_dir" ]; then
        echo "❌ Error: OAuth account '$name' not found."
        echo "Available accounts:"
        _kilo_oauth_list
        exit 1
    fi

    if [ ! -f "$source_creds" ]; then
        echo "❌ Error: No auth.json found for account '$name'."
        exit 1
    fi

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
    echo "Now run 'kilo' to use this account."
}

_kilo_oauth_current() {
    local current="$KILO_AUTH_FILE"
    
    if [ ! -f "$current" ]; then
        echo "No active OAuth account (no auth.json found)."
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

    local dir="$(_kilo_oauth_dir)"
    local current_hash
    current_hash=$(_hash_file "$current")
    
    for account_dir in "$dir"/*/; do
        [ -d "$account_dir" ] || continue
        local account_name
        account_name=$(basename "$account_dir")
        local account_creds="${account_dir}auth.json"
        
        if [ -f "$account_creds" ]; then
            local account_hash
            account_hash=$(_hash_file "$account_creds")
            if [ "$account_hash" = "$current_hash" ]; then
                echo "  Stored as: $account_name"
                return
            fi
        fi
    done
    
    echo "  Stored as: (not stored - run 'kilo-env.sh oauth-create' to save)"
}

_kilo_oauth_delete() {
    local name="${1:-}"

    if [ -z "$name" ]; then
        echo "❌ Error: Account name required."
        echo "Usage: kilo-env.sh oauth-delete <name>"
        exit 1
    fi

    local target_dir="$(_kilo_oauth_dir)/$name"

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

# ─── Kilo CLI environment variables ──────────────────────────────────────────

KILO_PROVIDER_VARS=(
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
    "KILO_API_KEY"
    "KILO_ORG_ID"
    "KILO_OAUTH_TOKEN"
    "KILO_AUTH_FILE"
)

KILO_SECRET_VARS=(
    "ANTHROPIC_API_KEY"
    "OPENAI_API_KEY"
    "GEMINI_API_KEY"
    "GROQ_API_KEY"
    "OPENROUTER_API_KEY"
    "XAI_API_KEY"
    "AZURE_OPENAI_API_KEY"
    "AWS_ACCESS_KEY_ID"
    "AWS_SECRET_ACCESS_KEY"
    "GITHUB_TOKEN"
    "KILO_API_KEY"
    "KILO_OAUTH_TOKEN"
)

# ─── Usage ────────────────────────────────────────────────────────────────────

usage() {
    cat << 'USAGE'
Kilo CLI Account Manager (Environment-based)

Usage: kilo-env.sh <command> [arguments]

Commands:
  list                  List available accounts
  create <name>         Create new account config
  show <name>           Show account configuration (keys masked)
  edit <name>           Edit account config in $EDITOR
  validate <name>       Validate account config syntax
  <name>                Export account env vars to current shell
  <name> <command>      Run command with account credentials

OAuth Commands (for switching between Kilo accounts):
  oauth-list                  List stored OAuth accounts
  oauth-create <name>         Save current OAuth creds as account
  oauth-switch <name>         Switch to stored OAuth account
  oauth-current               Show current OAuth account info
  oauth-delete <name>         Delete stored OAuth account
  oauth-login                 Clear creds and trigger new login

Flags:
  DRY_RUN=1             Preview actions without executing

Accounts directory: <dynamic>

Examples:
  kilo-env.sh create work
  kilo-env.sh work                       # Export vars for current shell
  kilo-env.sh work kilo                 # Run kilo with work account
  kilo-env.sh edit work                 # Edit in $EDITOR
  kilo-env.sh validate work             # Check config syntax
  DRY_RUN=1 kilo-env.sh work kilo      # Preview without running

OAuth Examples:
  kilo-env.sh oauth-create work        # Save current logged-in account
  kilo-env.sh oauth-create personal    # Save another account
  kilo-env.sh oauth-switch work        # Switch to work account
  kilo-env.sh oauth-list               # List stored OAuth accounts
  kilo-env.sh oauth-current            # Show current OAuth info

Environment Variables (supported in account files):
  ANTHROPIC_API_KEY     Anthropic provider key
  OPENAI_API_KEY        OpenAI provider key
  GEMINI_API_KEY        Google Gemini key
  GROQ_API_KEY          Groq key
  OPENROUTER_API_KEY    OpenRouter key
  XAI_API_KEY           xAI (Grok) key
  AZURE_OPENAI_ENDPOINT Azure OpenAI endpoint
  AZURE_OPENAI_API_KEY  Azure OpenAI key
  AWS_ACCESS_KEY_ID     AWS Bedrock access key
  AWS_SECRET_ACCESS_KEY AWS Bedrock secret key
  AWS_REGION            AWS region
  GITHUB_TOKEN          GitHub Copilot token
  KILO_API_KEY          Kilo Gateway API key
  KILO_ORG_ID           Kilo Gateway organization ID
  KILO_OAUTH_TOKEN      OAuth token for headless/non-interactive usage
  KILO_AUTH_FILE        Custom auth.json path (default: ~/.local/share/kilo/auth.json)

Kilo Configuration:
  Config file:  ~/.config/kilo/kilo.jsonc
  Keys use {env:VAR_NAME} syntax — e.g. {env:ANTHROPIC_API_KEY}
  Auth storage: ~/.local/share/kilo/auth.json (OAuth)
USAGE
    exit 0
}

# ─── List Accounts ────────────────────────────────────────────────────────────

list_accounts() {
    if [ ! -d "$KILO_ACCOUNTS_DIR" ]; then
        echo "No accounts found."
        echo "Create one with: kilo-env.sh create <name>"
        return
    fi

    local has_accounts=false
    echo "Available accounts:"
    echo ""

    # Compute hash of current shell's secret vars
    local current_hash=""
    local combined=""
    for var in "${KILO_SECRET_VARS[@]}"; do
        local val="${!var:-}"
        if [ -n "$val" ]; then
            combined="${combined}${var}=${val}:"
        fi
    done
    if [ -n "$combined" ]; then
        current_hash=$(_hash_string "$combined")
    fi

    shopt -s nullglob 2>/dev/null || true
    local files=("$KILO_ACCOUNTS_DIR"/*.env)
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
            for var in "${KILO_SECRET_VARS[@]}"; do
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

        # Detect OAuth providers from auth.json
        local oauth_providers=()
        if [ -f "$KILO_AUTH_FILE" ] && command -v python3 &>/dev/null; then
            while IFS= read -r prov; do
                [ -n "$prov" ] && oauth_providers+=("$prov")
            done < <(python3 -c '
import json, sys
try:
    data = json.load(open(sys.argv[1]))
    for name, entry in data.items():
        if entry.get("type") == "oauth":
            print(name)
except:
    pass
' "$KILO_AUTH_FILE" 2>/dev/null || true)
        fi

        # Show configured providers
        local providers=()
        for var in "${KILO_PROVIDER_VARS[@]}"; do
            local val
            val=$(_grep_env_key "$var" "$file")
            if [ -n "$val" ]; then
                case "$var" in
                    ANTHROPIC_API_KEY) providers+=("anthropic") ;;
                    OPENAI_API_KEY) providers+=("openai") ;;
                    GEMINI_API_KEY) providers+=("gemini") ;;
                    GROQ_API_KEY) providers+=("groq") ;;
                    OPENROUTER_API_KEY) providers+=("openrouter") ;;
                    XAI_API_KEY) providers+=("xai") ;;
                    AZURE_OPENAI_API_KEY) providers+=("azure") ;;
                    AWS_ACCESS_KEY_ID) providers+=("bedrock") ;;
                    GITHUB_TOKEN) providers+=("github") ;;
                    KILO_API_KEY) providers+=("kilo-gateway") ;;
                esac
            fi
        done

        # Add OAuth providers (deduplicated)
        for prov in "${oauth_providers[@]}"; do
            local already=false
            for p in "${providers[@]}"; do
                [ "$p" = "$prov" ] && already=true && break
            done
            [ "$already" = false ] && providers+=("$prov(oauth)")
        done

        local info=""
        if [ ${#providers[@]} -gt 0 ]; then
            info=$(IFS=','; echo "${providers[*]}")
        fi

        if [ -n "$info" ]; then
            echo "  • ${name}${marker}  ($info)"
        else
            echo "  • ${name}${marker}"
        fi
    done

    if [ "$has_accounts" = false ]; then
        echo "No accounts found."
        echo "Create one with: kilo-env.sh create <name>"
    fi

    echo ""
    echo "Accounts directory: $KILO_ACCOUNTS_DIR"
}

# ─── Create Account ───────────────────────────────────────────────────────────

create_account() {
    local name="${1:-}"

    if [ -z "$name" ]; then
        echo "❌ Error: Account name required."
        echo "Usage: kilo-env.sh create <name>"
        exit 1
    fi

    if [[ ! "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo "❌ Error: Account name can only contain letters, numbers, hyphens, and underscores."
        exit 1
    fi

    mkdir -p "$KILO_ACCOUNTS_DIR"

    local file="$KILO_ACCOUNTS_DIR/$name.env"

    if [ -f "$file" ]; then
        echo "❌ Error: Account '$name' already exists."
        echo "Edit it with: kilo-env.sh edit $name"
        exit 1
    fi

    cat > "$file" << 'EOF'
# Kilo CLI Account Configuration
# Set API keys for the providers you want to use.
# These env vars are referenced in ~/.config/kilo/kilo.jsonc
# via {env:VAR_NAME} syntax — never hardcode keys in kilo.jsonc.

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

# ─── GitHub Copilot (OAuth alternative) ─────────────────────────
# GITHUB_TOKEN=ghp_your-token

# ─── OAuth Token (headless/non-interactive) ─────────────────────
# For remote/headless servers where browser OAuth is not possible
# Generate token on an interactive machine, then copy here:
# KILO_OAUTH_TOKEN=your-oauth-token-here
#
# Alternative: Copy ~/.local/share/kilo/auth.json from interactive machine
# Or set custom auth file path:
# KILO_AUTH_FILE=/path/to/custom/auth.json

# ─── Kilo Gateway (optional) ────────────────────────────────────
# KILO_API_KEY=kilo_your-key
# KILO_ORG_ID=your-org-id
EOF

    chmod 600 "$file"

    echo "✅ Created account: $name"
    echo "Config file: $file"
    echo ""
    echo "Next steps:"
    echo "  1. Edit the file: kilo-env.sh edit $name"
    echo "  2. Uncomment and set your API keys"
    echo "  3. Activate: kilo-env.sh $name"
    echo "  4. Ensure ~/.config/kilo/kilo.jsonc uses {env:VAR_NAME} syntax"
    echo "  5. Run: kilo"
    echo ""
    echo "Or run directly: kilo-env.sh $name kilo"
}

# ─── Show Account ─────────────────────────────────────────────────────────────

show_account() {
    local name="${1:-}"
    local file="$KILO_ACCOUNTS_DIR/$name.env"

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

    echo "Configured credentials:"

    local has_creds=false
    for var in "${KILO_PROVIDER_VARS[@]}"; do
        local file_val
        file_val=$(_grep_env_key "$var" "$file")
        if [ -n "$file_val" ]; then
            has_creds=true
            # Check if this is a secret var
            local is_secret=false
            for sv in "${KILO_SECRET_VARS[@]}"; do
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
    local file="$KILO_ACCOUNTS_DIR/$name.env"

    if [ ! -f "$file" ]; then
        echo "❌ Error: Account '$name' not found."
        echo "Create it with: kilo-env.sh create $name"
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
    local file="$KILO_ACCOUNTS_DIR/$name.env"

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
}

# ─── Load Account ─────────────────────────────────────────────────────────────

load_account() {
    local name="$1"
    local file="$KILO_ACCOUNTS_DIR/$name.env"

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
    for var in "${KILO_SECRET_VARS[@]}"; do
        local val="${!var:-}"
        if [ -n "$val" ]; then
            case "$var" in
                ANTHROPIC_API_KEY) active_providers+=("anthropic") ;;
                OPENAI_API_KEY) active_providers+=("openai") ;;
                GEMINI_API_KEY) active_providers+=("gemini") ;;
                GROQ_API_KEY) active_providers+=("groq") ;;
                OPENROUTER_API_KEY) active_providers+=("openrouter") ;;
                XAI_API_KEY) active_providers+=("xai") ;;
                AZURE_OPENAI_API_KEY) active_providers+=("azure") ;;
                AWS_ACCESS_KEY_ID) active_providers+=("bedrock") ;;
                GITHUB_TOKEN) active_providers+=("github") ;;
                KILO_API_KEY) active_providers+=("kilo-gateway") ;;
                KILO_OAUTH_TOKEN) active_providers+=("kilo-oauth") ;;
            esac
        fi
    done

    # Check OAuth token status
    if [ -n "${KILO_OAUTH_TOKEN:-}" ]; then
        echo "  OAuth Token: $(_mask_value "$KILO_OAUTH_TOKEN")"
    fi
    if [ -n "${KILO_AUTH_FILE:-}" ]; then
        echo "  Auth File: ${KILO_AUTH_FILE}"
    fi

    # Detect OAuth providers from auth.json
    local auth_file_to_check="${KILO_AUTH_FILE:-$KILO_AUTH_FILE}"
    if [ -f "$auth_file_to_check" ] && command -v python3 &>/dev/null; then
        while IFS= read -r prov; do
            [ -n "$prov" ] && active_providers+=("$prov(oauth)")
        done < <(python3 -c '
import json, sys
try:
    data = json.load(open(sys.argv[1]))
    for name, entry in data.items():
        if entry.get("type") == "oauth":
            print(name)
except:
    pass
' "$auth_file_to_check" 2>/dev/null || true)
    fi

    if [ ${#active_providers[@]} -gt 0 ]; then
        echo "  Providers: $(IFS=','; echo "${active_providers[*]}")"
    fi

    echo ""
    echo "Environment variables exported to current shell."
    echo "These are read by ~/.config/kilo/kilo.jsonc via {env:VAR_NAME} syntax."
    echo "OAuth providers use credentials from $KILO_AUTH_FILE."
    echo "Run 'kilo' to start with this account."
}

# ─── Run With Account ─────────────────────────────────────────────────────────

run_with_account() {
    local name="$1"
    shift

    local file="$KILO_ACCOUNTS_DIR/$name.env"

    if [ ! -f "$file" ]; then
        echo "❌ Error: Account '$name' not found at $file"
        exit 1
    fi

    # Validate directory permissions before sourcing
    local dir_perms
    if stat -f '%A' "$KILO_ACCOUNTS_DIR" 2>/dev/null; then
        dir_perms=$(stat -f '%A' "$KILO_ACCOUNTS_DIR")
    elif stat -c '%a' "$KILO_ACCOUNTS_DIR" 2>/dev/null; then
        dir_perms=$(stat -c '%a' "$KILO_ACCOUNTS_DIR")
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
            echo "Usage: kilo-env.sh $name <command> [args...]"
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
        _kilo_oauth_list
        ;;
    oauth-create)
        _kilo_oauth_create "${2:-}"
        ;;
    oauth-switch)
        _kilo_oauth_switch "${2:-}"
        ;;
    oauth-current)
        _kilo_oauth_current
        ;;
    oauth-delete)
        _kilo_oauth_delete "${2:-}"
        ;;
    oauth-login)
        rm -f "$KILO_AUTH_FILE"
        echo "✅ Cleared OAuth credentials."
        echo "Run 'kilo' to log in with a different account."
        ;;
    ""|--help|-h|help)
        usage
        ;;
    *)
        if [ -f "$KILO_ACCOUNTS_DIR/$1.env" ]; then
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
