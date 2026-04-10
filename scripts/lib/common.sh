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
