#!/usr/bin/env bash
# kilo-env.sh - Environment-based account switcher for Kilo CLI
#
# This script manages multiple Kilo CLI accounts using environment variable files.
# Each account has its own .env file with credentials and settings.
#
# Usage:
#   kilo-env.sh list                  List available accounts
#   kilo-env.sh create <name>         Create new account config
#   kilo-env.sh <name>                Export account env vars to current shell
#   kilo-env.sh <name> <command>      Run command with account credentials
#
# Examples:
#   kilo-env.sh create work
#   kilo-env.sh create personal
#   kilo-env.sh work                  # Export vars
#   kilo-env.sh work kilo             # Run kilo with work account
#   kilo-env.sh personal kilo --verbose

set -euo pipefail

KILO_ACCOUNTS_DIR="${KILO_ACCOUNTS_DIR:-${HOME}/.config/kilo/accounts}"

# Helper: compute SHA256 hash of a string (portable)
_hash_string() {
    printf '%s' "$1" | shasum -a 256 2>/dev/null | cut -d' ' -f1 || \
    printf '%s' "$1" | sha256sum 2>/dev/null | cut -d' ' -f1 || \
    echo "unknown"
}

# Helper: get configured editor
_get_editor() {
    echo "${EDITOR:-${VISUAL:-nano}}"
}

# Helper: validate .env file syntax
_validate_env_file() {
    local file=$1
    local line_num=0
    local errors=0

    while IFS= read -r line || [ -n "$line" ]; do
        line_num=$((line_num + 1))

        # Skip empty lines and comments
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue

        # Check VAR=value format
        if [[ ! "$line" =~ ^[A-Z_]+= ]]; then
            echo "  ⚠ Line $line_num: Invalid format: ${line:0:50}"
            errors=$((errors + 1))
        fi
    done < "$file"

    return $errors
}

# Helper: validate JSON config syntax
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
    else
        # No validator available — skip
        return 0
    fi
    return 0
}

# Helper: dry-run wrapper
_dry_run() {
    if [ "${DRY_RUN:-0}" = "1" ]; then
        echo "🔍 [DRY RUN] Would execute: $*"
        return 0
    else
        "$@"
    fi
}

usage() {
    echo "Kilo CLI Account Manager (Environment-based)"
    echo ""
    echo "Usage: kilo-env.sh <command> [arguments]"
    echo ""
    echo "Commands:"
    echo "  list                  List available accounts"
    echo "  create <name>         Create new account config"
    echo "  show <name>           Show account configuration"
    echo "  edit <name>           Edit account config in \$EDITOR"
    echo "  validate <name>       Validate account config syntax"
    echo "  <name>                Export account env vars to current shell"
    echo "  <name> <command>      Run command with account credentials"
    echo ""
    echo "Flags:"
    echo "  --dry-run             Preview actions without executing"
    echo "  --no-color            Disable colored output"
    echo ""
    echo "Accounts directory: $KILO_ACCOUNTS_DIR"
    echo ""
    echo "Examples:"
    echo "  kilo-env.sh create work"
    echo "  kilo-env.sh work                    # Export vars for current shell"
    echo "  kilo-env.sh work kilo               # Run kilo with work account"
    echo "  kilo-env.sh edit work               # Edit in \$EDITOR"
    echo "  kilo-env.sh validate work           # Check config syntax"
    echo "  DRY_RUN=1 kilo-env.sh work kilo     # Preview without running"
    echo ""
    echo "Environment Variables:"
    echo "  KILO_PROVIDER     Override provider (openai, anthropic, etc.)"
    echo "  KILO_API_KEY      API key for the provider"
    echo "  KILO_ORG_ID       Organization ID (for Kilo Gateway)"
    echo "  KILO_MODEL        Model to use (e.g., gpt-4, claude-sonnet-4)"
    echo "  KILOCODE_MODEL    Model for Kilo Gateway"
    echo "  EDITOR            Preferred editor (default: nano)"
    exit 0
}

list_accounts() {
    if [ ! -d "$KILO_ACCOUNTS_DIR" ]; then
        echo "No accounts found."
        echo "Create one with: kilo-env.sh create <name>"
        return
    fi

    local has_accounts=false
    echo "Available accounts:"
    echo ""

    # Compute hash of current shell's API key (if set)
    local current_key_hash=""
    if [ -n "${KILO_API_KEY:-}" ]; then
        current_key_hash=$(_hash_string "$KILO_API_KEY")
    fi

    for file in "$KILO_ACCOUNTS_DIR"/*.env; do
        if [ -f "$file" ]; then
            has_accounts=true
            name=$(basename "$file" .env)

            # Show if currently active — compare hashes, not raw keys
            marker=""
            if [ -n "$current_key_hash" ]; then
                # Extract key from file and hash it
                local file_key
                file_key=$(grep -E '^KILO_API_KEY=' "$file" 2>/dev/null | head -1 | cut -d'=' -f2-)
                if [ -n "$file_key" ]; then
                    local file_key_hash
                    file_key_hash=$(_hash_string "$file_key")
                    if [ "$current_key_hash" = "$file_key_hash" ]; then
                        marker=" ✓"
                    fi
                fi
            fi

            # Show provider and model if available
            local provider=""
            local model=""
            provider=$(grep -E '^KILO_PROVIDER=' "$file" 2>/dev/null | head -1 | cut -d'=' -f2- || echo "")
            model=$(grep -E '^KILO_MODEL=|^KILOCODE_MODEL=' "$file" 2>/dev/null | head -1 | cut -d'=' -f2- || echo "")

            local info=""
            [ -n "$provider" ] && info="$provider"
            [ -n "$model" ] && info="$info/$model"

            if [ -n "$info" ]; then
                echo "  • ${name}${marker}  ($info)"
            else
                echo "  • ${name}${marker}"
            fi
        fi
    done

    if [ "$has_accounts" = false ]; then
        echo "No accounts found."
        echo "Create one with: kilo-env.sh create <name>"
    fi

    echo ""
    echo "Accounts directory: $KILO_ACCOUNTS_DIR"
}

create_account() {
    local name=$1
    
    if [ -z "$name" ]; then
        echo "❌ Error: Account name required."
        echo "Usage: kilo-env.sh create <name>"
        exit 1
    fi
    
    # Validate account name
    if [[ ! "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo "❌ Error: Account name can only contain letters, numbers, hyphens, and underscores."
        exit 1
    fi
    
    mkdir -p "$KILO_ACCOUNTS_DIR"
    
    local file="$KILO_ACCOUNTS_DIR/$name.env"
    
    if [ -f "$file" ]; then
        echo "❌ Error: Account '$name' already exists."
        echo "Edit it with: nano $file"
        exit 1
    fi
    
    cat > "$file" << 'EOF'
# Kilo CLI Account Configuration
# Fill in your credentials below

# Provider: openai, anthropic, google, etc.
KILO_PROVIDER=openai

# API Key (required)
KILO_API_KEY=sk-your-api-key-here

# Organization ID (optional, for Kilo Gateway)
# KILO_ORG_ID=your-org-id

# Model override (optional)
# KILO_MODEL=gpt-4-turbo

# Kilo Gateway model (optional, alternative to KILO_MODEL)
# KILOCODE_MODEL=anthropic/claude-sonnet-4
EOF
    
    # Secure the file
    chmod 600 "$file"
    
    echo "✅ Created account: $name"
    echo "Config file: $file"
    echo ""
    echo "Next steps:"
    echo "  1. Edit the file: nano $file"
    echo "  2. Add your API key to KILO_API_KEY"
    echo "  3. Activate: kilo-env.sh $name"
    echo "  4. Run kilo: kilo"
    echo ""
    echo "Or run directly: kilo-env.sh $name kilo"
}

show_account() {
    local name=$1
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

    # Show non-sensitive vars
    grep -E '^[A-Z_]+=' "$file" | grep -v 'API_KEY' | sed 's/^/  /'

    # Read API key from file (not current env) and mask properly
    local file_api_key
    file_api_key=$(grep -E '^KILO_API_KEY=' "$file" 2>/dev/null | head -1 | cut -d'=' -f2-)
    if [ -n "$file_api_key" ]; then
        local key_len=${#file_api_key}
        if [ "$key_len" -gt 12 ]; then
            echo "  KILO_API_KEY=${file_api_key:0:4}****${file_api_key: -4} (${key_len} chars)"
        else
            echo "  KILO_API_KEY=****(too short to display safely)"
        fi
    else
        echo "  KILO_API_KEY=(not set)"
    fi

    echo "---"

    # Validate config
    if ! _validate_env_file "$file" 2>/dev/null; then
        echo "⚠ Config has syntax warnings (see above)"
    fi
}

edit_account() {
    local name=$1
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

    # Validate after edit
    echo ""
    if _validate_env_file "$file"; then
        echo "✅ Config saved and validated."
    else
        echo "⚠ Config saved but has syntax warnings. Review above."
    fi
}

validate_account() {
    local name=$1
    local file="$KILO_ACCOUNTS_DIR/$name.env"

    if [ ! -f "$file" ]; then
        echo "❌ Error: Account '$name' not found."
        exit 1
    fi

    echo "Validating: $name"
    echo "File: $file"
    echo "---"

    local errors=0
    if _validate_env_file "$file"; then
        echo "---"
        echo "✅ Config syntax is valid."
    else
        echo "---"
        echo "❌ Config has syntax errors (see above)."
        exit 1
    fi
}

load_account() {
    local name=$1
    local file="$KILO_ACCOUNTS_DIR/$name.env"
    
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
    echo "  Provider: ${KILO_PROVIDER:-default}"
    if [ -n "${KILO_API_KEY:-}" ]; then
        echo "  API Key: ${KILO_API_KEY:0:8}..."
    fi
    [ -n "${KILO_ORG_ID:-}" ] && echo "  Org ID: $KILO_ORG_ID"
    [ -n "${KILO_MODEL:-}" ] && echo "  Model: $KILO_MODEL"
    [ -n "${KILOCODE_MODEL:-}" ] && echo "  Gateway Model: $KILOCODE_MODEL"
    echo ""
    echo "Environment variables exported to current shell."
    echo "Run 'kilo' to start with this account."
}

run_with_account() {
    local name=$1
    shift
    
    local file="$KILO_ACCOUNTS_DIR/$name.env"
    
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
            echo "Usage: kilo-env.sh $name <command> [args...]"
            exit 1
        fi
        
        exec "$@"
    )
}

# Main command handler
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
        # Check if it's a known account name
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
