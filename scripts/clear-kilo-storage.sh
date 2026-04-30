#!/usr/bin/env bash
#
# clear-kilo-storage.sh - Clear Kilo CLI storage files (kilo.db, accounts, oauth, snapshots)
#
# This script clears various Kilo CLI storage components:
#   - SQLite database (kilo.db, kilo.db-wal, kilo.db-shm)
#   - Account environment files (~/.config/kilo/accounts/)
#   - OAuth token storage (~/.local/share/kilo/auth.json and ~/.config/kilo/oauth-accounts/)
#   - Snapshot/backup files (if any)
#
# Usage:
#   ./clear-kilo-storage.sh [options]
#
# Options:
#   --db          Clear kilo database files (default)
#   --accounts    Clear account environment files
#   --oauth       Clear OAuth token storage
#   --snapshot    Clear snapshot/backup files
#   --all         Clear all storage components
#   --help        Show this help message
#
# Warning: This will delete data! Make sure Kilo is not running and you have backups if needed.
#
# Examples:
#   ./clear-kilo-storage.sh              # Clear database only (default)
#   ./clear-kilo-storage.sh --all        # Clear everything
#   ./clear-kilo-storage.sh --accounts   # Clear only account files
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

# Define Kilo directories (from kilo-env.sh defaults or environment)
KILO_ACCOUNTS_DIR="${KILO_ACCOUNTS_DIR:-${HOME}/.config/kilo/accounts}"
KILO_AUTH_FILE="${KILO_AUTH_FILE:-${HOME}/.local/share/kilo/auth.json}"
KILO_OAUTH_DIR="${KILO_OAUTH_DIR:-${HOME}/.config/kilo/oauth-accounts}"
KILO_DATA_DIR="${KILO_DATA_DIR:-${HOME}/.local/share/kilo}"

# Safety check: warn if Kilo processes might be running
if pgrep -i kilo >/dev/null 2>&1; then
    echo "⚠ Warning: Kilo processes appear to be running!"
    echo "   It is unsafe to delete storage while Kilo is active."
    echo "   Please stop Kilo before proceeding."
    read -rp "   Do you want to continue anyway? [y/N] " response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        echo "   Aborted."
        exit 0
    fi
fi

# Function to clear kilo database files
clear_database() {
    echo "🗑 Clearing Kilo database files..."
    local db_files=(
        "${KILO_DATA_DIR}/kilo.db"
        "${KILO_DATA_DIR}/kilo.db-wal"
        "${KILO_DATA_DIR}/kilo.db-shm"
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
    echo "   Checking for other database files in ${KILO_DATA_DIR}..."
    while IFS= read -r -d '' file; do
        if [[ "$file" =~ \.(db|sqlite|sqlite3)$ ]] && [[ ! "$file" =~ \-(wal|shm)$ ]]; then
            rm -f "$file"
            echo "   ✓ Removed database file: $file"
        fi
    done < <(find "${KILO_DATA_DIR}" -maxdepth 1 -type f -name "*.db*" -print0 2>/dev/null)
}

# Function to clear account environment files
clear_accounts() {
    echo "🗑 Clearing Kilo account environment files..."
    if [[ -d "$KILO_ACCOUNTS_DIR" ]]; then
        local account_files
        account_files=("$KILO_ACCOUNTS_DIR"/*.env)
        if [[ ${#account_files[@]} -gt 0 && -f "${account_files[0]}" ]]; then
            rm -f "${KILO_ACCOUNTS_DIR}"/*.env
            echo "   ✓ Removed ${#account_files[@]} account environment files from $KILO_ACCOUNTS_DIR"
        else
            echo "   ○ No account environment files found in $KILO_ACCOUNTS_DIR"
        fi
        
        # Remove empty directories
        if [[ -z "$(ls -A "$KILO_ACCOUNTS_DIR")" ]]; then
            rmdir "$KILO_ACCOUNTS_DIR"
            echo "   ✓ Removed empty accounts directory: $KILO_ACCOUNTS_DIR"
        fi
    else
        echo "   ○ Accounts directory does not exist: $KILO_ACCOUNTS_DIR"
    fi
}

# Function to clear OAuth token storage
clear_oauth() {
    echo "🗑 Clearing Kilo OAuth token storage..."
    
    # Clear auth.json
    if [[ -f "$KILO_AUTH_FILE" ]]; then
        rm -f "$KILO_AUTH_FILE"
        echo "   ✓ Removed: $KILO_AUTH_FILE"
    else
        echo "   ○ Auth file not found: $KILO_AUTH_FILE"
    fi
    
    # Clear OAuth accounts directory
    if [[ -d "$KILO_OAUTH_DIR" ]]; then
        local oauth_files
        oauth_files=("$KILO_OAUTH_DIR"/*)
        if [[ ${#oauth_files[@]} -gt 0 && -e "${oauth_files[0]}" ]]; then
            rm -rf "$KILO_OAUTH_DIR"/*
            echo "   ✓ Removed contents of OAuth directory: $KILO_OAUTH_DIR"
        else
            echo "   ○ OAuth directory is empty: $KILO_OAUTH_DIR"
        fi
        
        # Remove the directory itself if empty
        if [[ -z "$(ls -A "$KILO_OAUTH_DIR")" ]]; then
            rmdir "$KILO_OAUTH_DIR"
            echo "   ✓ Removed empty OAuth directory: $KILO_OAUTH_DIR"
        fi
    else
        echo "   ○ OAuth directory does not exist: $KILO_OAUTH_DIR"
    fi
}

# Function to clear snapshot/backup files
clear_snapshots() {
    echo "🗑 Clearing Kilo snapshot and backup files..."
    local snapshot_patterns=(
        "*snapshot*"
        "*backup*"
        "*.bak"
        "*.back"
        "*~"
        ".*.swp"
        ".*.swo"
        ".*.swn"
    )
    
    local search_dirs=(
        "$KILO_DATA_DIR"
        "$KILO_ACCOUNTS_DIR"
        "$KILO_OAUTH_DIR"
        "${HOME}/.config/kilo"
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
echo "🔧 Kilo Storage Cleanup Utility"
echo "================================"
echo

# Confirm before proceeding
read -rp "⚠ This will delete Kilo storage data. Continue? [y/N] " response
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

echo "✅ Kilo storage cleanup complete!"
echo
echo "📝 Notes:"
echo "   - You may need to restart any Kilo-dependent applications."
echo "   - Account configurations and OAuth tokens have been removed."
echo "   - To restore, you'll need to recreate accounts using 'kilo-env.sh create'."
echo
