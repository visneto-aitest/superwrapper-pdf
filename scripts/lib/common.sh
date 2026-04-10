#!/usr/bin/env bash
# lib/common.sh - Shared helper library for all AI CLI account management scripts
#
# Source this file from individual scripts:
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   source "$SCRIPT_DIR/../lib/common.sh"
#
# Requirements: bash 3.2+ (macOS compatible — no associative arrays in shared code)

set -euo pipefail

# ─── Helpers ──────────────────────────────────────────────────────────────────

# Compute SHA256 hash of a string (portable: macOS shasum or Linux sha256sum)
# Usage: _hash_string "my-secret-value"
_hash_string() {
    printf '%s' "$1" | shasum -a 256 2>/dev/null | cut -d' ' -f1 || \
    printf '%s' "$1" | sha256sum 2>/dev/null | cut -d' ' -f1 || \
    echo "unknown"
}

# Get configured editor (respects $EDITOR → $VISUAL → nano)
_get_editor() {
    printf '%s' "${EDITOR:-${VISUAL:-nano}}"
}

# Mask a sensitive value (show first 4 + last 4 chars)
# Usage: _mask_value "sk-ant-abc123xyz" → "sk-a****xyz (18 chars)"
_mask_value() {
    local val="$1"
    local len=${#val}
    if [ "$len" -gt 12 ]; then
        printf '%s' "${val:0:4}****${val: -4} (${len} chars)"
    elif [ "$len" -gt 0 ]; then
        printf '%s' "****(masked)"
    else
        printf '%s' "(not set)"
    fi
}

# Validate .env file syntax (KEY=value format, allows comments and blanks)
# Returns 0 if valid, 1 if any errors found
_validate_env_file() {
    local file="$1"
    local line_num=0
    local errors=0

    while IFS= read -r line || [ -n "$line" ]; do
        line_num=$((line_num + 1))
        # Skip empty lines and comments
        case "$line" in
            ""|\#*|" "*) 
                # Allow lines starting with whitespace then #
                local trimmed
                trimmed="${line#"${line%%[![:space:]]*}"}"
                case "$trimmed" in
                    ""|\#*) continue ;;
                esac
                ;;
        esac
        # Check KEY=value format (alphanumeric + underscore key names)
        if [[ ! "$line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
            printf '  ⚠ Line %d: Invalid format: %.50s\n' "$line_num" "$line"
            errors=$((errors + 1))
        fi
    done < "$file"

    if [ "$errors" -gt 0 ]; then
        return 1
    fi
    return 0
}

# Validate JSON syntax using python3 or jq (safe from command injection)
# Usage: _validate_json "/path/to/file.json"
_validate_json() {
    local file="$1"
    if command -v python3 &>/dev/null; then
        # Pass file as argv argument — never interpolated into Python code
        if ! python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$file" 2>/dev/null; then
            return 1
        fi
    elif command -v jq &>/dev/null; then
        if ! jq empty "$file" 2>/dev/null; then
            return 1
        fi
    else
        # No validator available — assume valid (can't check)
        return 0
    fi
    return 0
}

# Dry-run wrapper: if DRY_RUN=1, print action instead of executing
# Usage: _dry_run cp source dest
_dry_run() {
    if [ "${DRY_RUN:-0}" = "1" ]; then
        printf '🔍 [DRY RUN] Would execute: %s\n' "$*"
        return 0
    else
        "$@"
    fi
}

# Backup a file with timestamp (preserves permissions)
# Usage: _backup_file "/path/to/file.json"
_backup_file() {
    local file="$1"
    if [ -f "$file" ]; then
        local dir base timestamp
        dir=$(dirname "$file")
        base=$(basename "$file")
        timestamp=$(date +%Y%m%d_%H%M%S)
        local backup="${dir}/${base}.backup_${timestamp}"
        cp "$file" "$backup"
        chmod 600 "$backup"
        printf '  ✓ Backed up to: %s\n' "$(basename "$backup")"
    fi
}

# Check if a variable name is in a list (bash 3.2 compatible — no associative arrays)
# Usage: _var_in_list "SECRET_KEY" "KEY1 KEY2 KEY3"
_var_in_list() {
    local var="$1"
    local list="$2"
    local item
    for item in $list; do
        [ "$var" = "$item" ] && return 0
    done
    return 1
}

# Safely grep a key from an env file (avoids set -eo pipefail issues)
# Usage: _grep_env_key "API_KEY" "/path/to/file.env"
_grep_env_key() {
    local key="$1"
    local file="$2"
    local result=""
    result=$(grep -E "^${key}=" "$file" 2>/dev/null | head -1 | cut -d'=' -f2-) || result=""
    printf '%s' "$result"
}

# Compare two files by hashing specific keys (for active account detection)
# Builds a combined hash of all secret vars from a file
# Usage: _hash_account_file "/path/to/file.env" "SECRET_VAR1 SECRET_VAR2"
_hash_account_file() {
    local file="$1"
    local secret_vars="$2"
    local combined=""
    local var val
    for var in $secret_vars; do
        val=$(_grep_env_key "$var" "$file")
        if [ -n "$val" ]; then
            combined="${combined}${var}=${val}:"
        fi
    done
    if [ -n "$combined" ]; then
        _hash_string "$combined"
    else
        echo ""
    fi
}

# List directory contents (safe glob with nullglob)
# Usage: _list_files "*.env" "/path/to/dir"
_list_files() {
    local pattern="$1"
    local dir="$2"
    local found=false
    local f
    for f in "$dir"/$pattern; do
        [ -f "$f" ] || continue
        found=true
        printf '%s\n' "$f"
    done
    if [ "$found" = false ]; then
        return 1
    fi
    return 0
}

# Validate a name is safe for use as account/profile identifier
_validate_name() {
    local name="$1"
    local label="${2:-name}"
    if [ -z "$name" ]; then
        printf '❌ Error: %s name required.\n' "$label"
        return 1
    fi
    if [[ ! "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        printf '❌ Error: %s name can only contain letters, numbers, hyphens, and underscores.\n' "$label"
        return 1
    fi
    return 0
}

# ─── OAuth Token Helpers ──────────────────────────────────────────────────────

# Import OAuth token to CLI auth storage
# Usage: _import_oauth_token "claude" "your-token-here"
# Supported tools: claude, opencode, gemini, kilo, codex
_import_oauth_token() {
    local tool="$1"
    local token="$2"
    
    if [ -z "$tool" ] || [ -z "$token" ]; then
        printf '❌ Error: Tool name and token required.\n'
        printf 'Usage: _import_oauth_token <tool> <token>\n'
        printf 'Supported tools: claude, opencode, gemini, kilo, codex\n'
        return 1
    fi
    
    case "$tool" in
        claude)
            local auth_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
            local auth_file="$auth_dir/.credentials.json"
            mkdir -p "$auth_dir"
            printf '{"claudeAiOauth":{"type":"oauth","access":"%s","refresh":"","expires":0}}' "$token" > "$auth_file"
            chmod 600 "$auth_file"
            printf '✅ OAuth token imported to: %s\n' "$auth_file"
            ;;
        opencode)
            local auth_file="$HOME/.local/share/opencode/auth.json"
            mkdir -p "$(dirname "$auth_file")"
            printf '{"provider":{"type":"oauth","access":"%s","refresh":"","expires":0}}' "$token" > "$auth_file"
            chmod 600 "$auth_file"
            printf '✅ OAuth token imported to: %s\n' "$auth_file"
            ;;
        gemini)
            local auth_file="$HOME/.gemini/credentials.json"
            mkdir -p "$(dirname "$auth_file")"
            printf '{"type":"oauth","access_token":"%s","refresh_token":"","expires_in":3600}' "$token" > "$auth_file"
            chmod 600 "$auth_file"
            printf '✅ OAuth token imported to: %s\n' "$auth_file"
            ;;
        kilo)
            local auth_file="$HOME/.local/share/kilo/auth.json"
            mkdir -p "$(dirname "$auth_file")"
            printf '{"kilo":{"type":"oauth","access":"%s","refresh":"","expires":0}}' "$token" > "$auth_file"
            chmod 600 "$auth_file"
            printf '✅ OAuth token imported to: %s\n' "$auth_file"
            ;;
        codex)
            local auth_file="$HOME/.codex/auth.json"
            mkdir -p "$(dirname "$auth_file")"
            printf '{"type":"oauth","access_token":"%s","refresh_token":"","expires_in":3600}' "$token" > "$auth_file"
            chmod 600 "$auth_file"
            printf '✅ OAuth token imported to: %s\n' "$auth_file"
            printf '⚠ Note: Codex OAuth support is limited. OPENAI_API_KEY is recommended for headless usage.\n'
            ;;
        *)
            printf '❌ Error: Unsupported tool: %s\n' "$tool"
            printf 'Supported tools: claude, opencode, gemini, kilo, codex\n'
            return 1
            ;;
    esac
    return 0
}

# Export OAuth token from CLI auth storage
# Usage: _export_oauth_token "claude"
# Returns token on stdout, or error message on stderr
_export_oauth_token() {
    local tool="$1"
    
    if [ -z "$tool" ]; then
        printf '❌ Error: Tool name required.\n' >&2
        printf 'Usage: _export_oauth_token <tool>\n' >&2
        return 1
    fi
    
    case "$tool" in
        claude)
            local auth_file="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.credentials.json"
            if [ ! -f "$auth_file" ]; then
                printf '❌ Error: No credentials found at %s\n' "$auth_file" >&2
                return 1
            fi
            python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["claudeAiOauth"]["access"])' "$auth_file" 2>/dev/null || \
                { printf '❌ Error: Failed to parse credentials\n' >&2; return 1; }
            ;;
        opencode)
            local auth_file="$HOME/.local/share/opencode/auth.json"
            if [ ! -f "$auth_file" ]; then
                printf '❌ Error: No credentials found at %s\n' "$auth_file" >&2
                return 1
            fi
            python3 -c 'import json,sys; data=json.load(open(sys.argv[1])); print(data.get("provider",{}).get("access",""))' "$auth_file" 2>/dev/null || \
                { printf '❌ Error: Failed to parse credentials\n' >&2; return 1; }
            ;;
        gemini)
            local auth_file="$HOME/.gemini/credentials.json"
            if [ ! -f "$auth_file" ]; then
                printf '❌ Error: No credentials found at %s\n' "$auth_file" >&2
                return 1
            fi
            python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("access_token",""))' "$auth_file" 2>/dev/null || \
                { printf '❌ Error: Failed to parse credentials\n' >&2; return 1; }
            ;;
        kilo)
            local auth_file="${KILO_AUTH_FILE:-$HOME/.local/share/kilo/auth.json}"
            if [ ! -f "$auth_file" ]; then
                printf '❌ Error: No credentials found at %s\n' "$auth_file" >&2
                return 1
            fi
            python3 -c 'import json,sys; data=json.load(open(sys.argv[1])); print(list(data.values())[0].get("access",""))' "$auth_file" 2>/dev/null || \
                { printf '❌ Error: Failed to parse credentials\n' >&2; return 1; }
            ;;
        codex)
            local auth_file="$HOME/.codex/auth.json"
            if [ ! -f "$auth_file" ]; then
                printf '❌ Error: No credentials found at %s\n' "$auth_file" >&2
                return 1
            fi
            python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("access_token",""))' "$auth_file" 2>/dev/null || \
                { printf '❌ Error: Failed to parse credentials\n' >&2; return 1; }
            ;;
        *)
            printf '❌ Error: Unsupported tool: %s\n' "$tool" >&2
            printf 'Supported tools: claude, opencode, gemini, kilo, codex\n' >&2
            return 1
            ;;
    esac
    return 0
}

# Check OAuth token status for a tool
# Usage: _check_oauth_status "claude"
_check_oauth_status() {
    local tool="$1"
    
    case "$tool" in
        claude)
            local auth_file="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.credentials.json"
            ;;
        opencode)
            local auth_file="$HOME/.local/share/opencode/auth.json"
            ;;
        gemini)
            local auth_file="$HOME/.gemini/credentials.json"
            ;;
        kilo)
            local auth_file="${KILO_AUTH_FILE:-$HOME/.local/share/kilo/auth.json}"
            ;;
        codex)
            local auth_file="$HOME/.codex/auth.json"
            ;;
        *)
            printf '❓ OAuth status: Unknown tool "%s"\n' "$tool"
            return 1
            ;;
    esac
    
    if [ ! -f "$auth_file" ]; then
        printf '❓ OAuth status: No credentials found for %s\n' "$tool"
        return 1
    fi
    
    local has_token
    has_token=$(python3 -c '
import json, sys
try:
    data = json.load(open(sys.argv[1]))
    # Try different key structures
    for key in data:
        entry = data[key]
        if isinstance(entry, dict):
            if entry.get("type") == "oauth":
                token = entry.get("access") or entry.get("access_token", "")
                if token:
                    print("active")
                    sys.exit(0)
    print("inactive")
except Exception:
    print("error")
' "$auth_file" 2>/dev/null || echo "error")
    
    case "$has_token" in
        active)
            printf '✅ OAuth status: %s has active OAuth credentials\n' "$tool"
            return 0
            ;;
        inactive)
            printf '❓ OAuth status: %s credentials found but no valid token\n' "$tool"
            return 1
            ;;
        error)
            printf '❓ OAuth status: Unable to parse credentials for %s\n' "$tool"
            return 1
            ;;
    esac
}

# Copy OAuth credentials from one machine to another (via file)
# Usage: _copy_oauth_credentials "source_machine:path" "claude" "dest_path"
_copy_oauth_credentials() {
    local source="$1"
    local tool="$2"
    local dest="${3:-}"
    
    if [ -z "$source" ] || [ -z "$tool" ]; then
        printf '❌ Error: Source path and tool name required.\n'
        printf 'Usage: _copy_oauth_credentials <source_path> <tool> [dest_path]\n'
        return 1
    fi
    
    if [ ! -f "$source" ]; then
        printf '❌ Error: Source file not found: %s\n' "$source"
        return 1
    fi
    
    # Determine destination path
    case "$tool" in
        claude)
            dest="${dest:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.credentials.json}"
            ;;
        opencode)
            dest="${dest:-$HOME/.local/share/opencode/auth.json}"
            ;;
        gemini)
            dest="${dest:-$HOME/.gemini/credentials.json}"
            ;;
        kilo)
            dest="${dest:-$HOME/.local/share/kilo/auth.json}"
            ;;
        codex)
            dest="${dest:-$HOME/.codex/auth.json}"
            ;;
        *)
            printf '❌ Error: Unsupported tool: %s\n' "$tool"
            return 1
            ;;
    esac
    
    # Validate source is valid JSON
    if ! _validate_json "$source"; then
        printf '❌ Error: Source file is not valid JSON\n'
        return 1
    fi
    
    # Copy credentials
    mkdir -p "$(dirname "$dest")"
    cp "$source" "$dest"
    chmod 600 "$dest"
    
    printf '✅ OAuth credentials copied to: %s\n' "$dest"
    printf '⚠ Ensure this matches the source machine credentials\n'
    return 0
}

