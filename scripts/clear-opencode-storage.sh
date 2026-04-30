#!/usr/bin/env bash
#
# clear-opencode-storage.sh - Clear OpenCode CLI storage files (opencode.db, accounts, oauth, snapshots)
#
# This script clears various OpenCode CLI storage components:
#   - SQLite database (opencode.db, opencode.db-wal, opencode.db-shm)
#   - Account environment files (~/.config/opencode/accounts/)
#   - OAuth token storage (~/.local/share/opencode/auth.json and custom auth files)
#   - Snapshot/backup files (if any)
#
# Usage:
#   ./clear-opencode-storage.sh [options]
#
# Options:
#   --db          Clear opencode database files (default)
#   --accounts    Clear account environment files
#   --oauth       Clear OAuth token storage
#   --snapshot    Clear snapshot/backup files
#   --all         Clear all storage components
#   --help        Show this help message
#
# Warning: This will delete data! Make sure OpenCode is not running and you have backups if needed.
#
# Examples:
#   ./clear-opencode-storage.sh              # Clear database only (default)
#   ./clear-opencode-storage.sh --all        # Clear everything
#   ./clear-opencode-storage.sh --accounts   # Clear only account files
#
# Author: Assistant
# Created: $(date +%Y-%m-%d)
#

set -euo pipefail

# Default options
CLEAR_DB=false
CLEAR_ACCOUNTS=false
CLEAR_OAUTH=false
CLEAR_SNAPSHOT=false

# Help function
show_help() {
    grep '^#' "$0" | cut -c4-
    exit 0
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --db)
            CLEAR_DB=true
            shift
            ;;
        --accounts)
            CLEAR_ACCOUNTS=true
            shift
            ;;
        --oauth)
            CLEAR_OAUTH=true
            shift
            ;;
        --snapshot)
            CLEAR_SNAPSHOT=true
            shift
            ;;
        --all)
            CLEAR_DB=true
            CLEAR_ACCOUNTS=true
            CLEAR_OAUTH=true
            CLEAR_SNAPSHOT=true
            shift
            ;;
        --help|-h)
            show_help
            ;;
        *)
            echo "❌ Error: Unknown option: $1"
            echo "Run '$0 --help' for usage information."
            exit 1
            ;;
    esac
done

# If no options specified, default to clearing database
if [[ "$CLEAR_DB" == false && "$CLEAR_ACCOUNTS" == false && "$CLEAR_OAUTH" == false && "$CLEAR_SNAPSHOT" == false ]]; then
    CLEAR_DB=true
fi

# Define OpenCode directories (from opencode-env.sh defaults or environment)
OPENCODE_ACCOUNTS_DIR="${OPENCODE_ACCOUNTS_DIR:-${HOME}/.config/opencode/accounts}"
OPENCODE_AUTH_FILE="${OPENCODE_AUTH_FILE:-${HOME}/.local/share/opencode/auth.json}"
OPENCODE_DATA_DIR="${HOME}/.local/share/opencode"

# Safety check: warn if OpenCode processes might be running
if pgrep -i opencode >/dev/null 2>&1; then
    echo "⚠ Warning: OpenCode processes appear to be running!"
    echo "   It is unsafe to delete storage while OpenCode is active."
    echo "   Please stop OpenCode before proceeding."
    read -rp "   Do you want to continue anyway? [y/N] " response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        echo "   Aborted."
        exit 0
    fi
fi

# Function to clear opencode database files
clear_database() {
    echo "🗑 Clearing OpenCode database files..."
    local db_files=(
        "${OPENCODE_DATA_DIR}/opencode.db"
        "${OPENCODE_DATA_DIR}/opencode.db-wal"
        "${OPENCODE_DATA_DIR}/opencode.db-shm"
    )
    
    for file in "${db_files[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            echo "   ✓ Removed: $file"
        else
            echo "   ○ Not found: $file"
        fi
    done
    
    # Also check for any other database-like files in the data directory
    echo "   Checking for other database files in ${OPENCODE_DATA_DIR}..."
    while IFS= read -r -d '' file; do
        if [[ "$file" =~ \.(db|sqlite|sqlite3)$ ]] && [[ ! "$file" =~ \-(wal|shm)$ ]]; then
            rm -f "$file"
            echo "   ✓ Removed database file: $file"
        fi
    done < <(find "${OPENCODE_DATA_DIR}" -maxdepth 1 -type f -name "*.db*" -print0 2>/dev/null)
}

# Function to clear account environment files
clear_accounts() {
    echo "🗑 Clearing OpenCode account environment files..."
    if [[ -d "$OPENCODE_ACCOUNTS_DIR" ]]; then
        local account_files
        account_files=("$OPENCODE_ACCOUNTS_DIR"/*.env)
        if [[ ${#account_files[@]} -gt 0 && -f "${account_files[0]}" ]]; then
            rm -f "${OPENCODE_ACCOUNTS_DIR}"/*.env
            echo "   ✓ Removed ${#account_files[@]} account environment files from $OPENCODE_ACCOUNTS_DIR"
        else
            echo "   ○ No account environment files found in $OPENCODE_ACCOUNTS_DIR"
        fi
        
        # Remove empty directories
        if [[ -z "$(ls -A "$OPENCODE_ACCOUNTS_DIR")" ]]; then
            rmdir "$OPENCODE_ACCOUNTS_DIR"
            echo "   ✓ Removed empty accounts directory: $OPENCODE_ACCOUNTS_DIR"
        fi
    else
        echo "   ○ Accounts directory does not exist: $OPENCODE_ACCOUNTS_DIR"
    fi
}

# Function to clear OAuth token storage
clear_oauth() {
    echo "🗑 Clearing OpenCode OAuth token storage..."
    
    # Clear default auth.json
    if [[ -f "$OPENCODE_AUTH_FILE" ]]; then
        rm -f "$OPENCODE_AUTH_FILE"
        echo "   ✓ Removed: $OPENCODE_AUTH_FILE"
    else
        echo "   ○ Auth file not found: $OPENCODE_AUTH_FILE"
    fi
    
    # Check for backup auth files in the data directory
    echo "   Checking for backup auth files in ${OPENCODE_DATA_DIR}..."
    while IFS= read -r -d '' file; do
        if [[ "$file" =~ auth.*\.(json|bak|backup) ]] && [[ "$file" != "$OPENCODE_AUTH_FILE" ]]; then
            rm -f "$file"
            echo "   ✓ Removed backup auth file: $file"
        fi
    done < <(find "${OPENCODE_DATA_DIR}" -maxdepth 1 -type f -name "auth*" -print0 2>/dev/null)
}

# Function to clear snapshot/backup files
clear_snapshots() {
    echo "🗑 Clearing OpenCode snapshot and backup files..."
    local snapshot_patterns=(
        "*snapshot*"
        "*backup*"
        "*.bak"
        "*.back"
        "*~"
        ".*.swp"
        ".*.swo"
        ".*.swn"
        "*.jsonc.bak"
        "*.json.bak"
        "*.json.backup-*"
        "opencode.*bak"
        "opencode.*.bak"
    )
    
    local search_dirs=(
        "$OPENCODE_DATA_DIR"
        "$OPENCODE_ACCOUNTS_DIR"
        "${HOME}/.config/opencode"
    )
    
    local found=false
    for dir in "${search_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            for pattern in "${snapshot_patterns[@]}"; do
                while IFS= read -r -d '' file; do
                    if [[ -f "$file" || -d "$file" ]]; then
                        if [[ -d "$file" ]]; then
                            rm -rf "$file"
                            echo "   ✓ Removed snapshot directory: $file"
                        else
                            rm -f "$file"
                            echo "   ✓ Removed snapshot file: $file"
                        fi
                        found=true
                    fi
                done < <(find "$dir" -maxdepth 3 -type f -name "$pattern" -print0 2>/dev/null)
            done
        fi
    done
    
    if [[ "$found" == false ]]; then
        echo "   ○ No snapshot or backup files found"
    fi
}

# Main execution
echo "🔧 OpenCode Storage Cleanup Utility"
echo "===================================="
echo

# Confirm before proceeding
read -rp "⚠ This will delete OpenCode storage data. Continue? [y/N] " response
if [[ ! "$response" =~ ^[Yy]$ ]]; then
    echo "   Aborted."
    exit 0
fi
echo

# Execute selected operations
if [[ "$CLEAR_DB" == true ]]; then
    clear_database
    echo
fi

if [[ "$CLEAR_ACCOUNTS" == true ]]; then
    clear_accounts
    echo
fi

if [[ "$CLEAR_OAUTH" == true ]]; then
    clear_oauth
    echo
fi

if [[ "$CLEAR_SNAPSHOT" == true ]]; then
    clear_snapshots
    echo
fi

echo "✅ OpenCode storage cleanup complete!"
echo
echo "📝 Notes:"
echo "   - You may need to restart any OpenCode-dependent applications."
echo "   - Account configurations and OAuth tokens have been removed."
echo "   - To restore, you'll need to recreate accounts using 'opencode-env.sh create'."
echo
