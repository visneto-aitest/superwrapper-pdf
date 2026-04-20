#!/usr/bin/env bash

# logs_cleanup.sh – safe, auditable log cleanup for coding agents
# ---------------------------------------------------------------
# Usage:
#   ./logs_cleanup.sh          # shows help
#   ./logs_cleanup.sh dry-run  # preview deletions
#   ./logs_cleanup.sh confirm  # interactive deletion with backup
# ---------------------------------------------------------------

# --------------------------------------------------------------------
# Configuration – add or remove log directories here as needed
# --------------------------------------------------------------------
LOG_PATHS=(
    "~/.local/share/kilo/log"
    "~/.pi/agent/logs"
    "~/.codex/sessions"
    "~/.codex/logs"
    "~/.claude/logs"
    "~/.claude/sessions"
    "~/.pi/agent/sessions"
)

# Where to store a temporary backup before deletion (timestamped)
BACKUP_ROOT="${HOME}/log_cleanup_backups"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_DIR="${BACKUP_ROOT}/backup_${TIMESTAMP}"

# Flags – default to dry‑run (safer)
DRY_RUN=true
CONFIRM=false

# --------------------------------------------------------------------
# Helper functions
# --------------------------------------------------------------------
expand_path() {
    # Expand leading ~ to $HOME, keep rest untouched
    local p="$1"
    [[ $p == ~/* ]] && p="${HOME}${p:1}"
    printf "%s" "$p"
}

path_exists() { [[ -d "$1" ]] ; }

# Count files recursively – silent on errors
file_count() {
    local d="$1"
    find "$d" -type f 2>/dev/null | wc -l
}

# List a sample of files (max 20) for user inspection
list_sample() {
    local d="$1"
    find "$d" -type f 2>/dev/null | head -20
}

# --------------------------------------------------------------------
# Argument parsing
# --------------------------------------------------------------------
show_help() {
    grep '^#' "$0" | sed -e 's/^# //'
    exit 0
}

while (( "$#" )); do
    case "$1" in
        dry-run)   DRY_RUN=true; shift ;;
        confirm)   CONFIRM=true; DRY_RUN=false; shift ;;
        -h|--help) show_help ;;
        *) echo "Unknown argument: $1"; show_help ;;
    esac
done

# --------------------------------------------------------------------
# Main workflow
# --------------------------------------------------------------------
printf "=== Log Cleanup Script ===\n"
printf "Dry‑run mode: %s\n" "$DRY_RUN"
printf "Confirm mode: %s\n\n" "$CONFIRM"

# 1️⃣ Scan directories and report totals
TOTAL=0
printf "Scanning log directories...\n"
for p in "${LOG_PATHS[@]}"; do
    dir=$(expand_path "$p")
    if path_exists "$dir"; then
        cnt=$(file_count "$dir")
        TOTAL=$((TOTAL+cnt))
        printf "  %s – %d files\n" "$dir" "$cnt"
    else
        printf "  %s – NOT FOUND\n" "$dir"
    fi
done

if (( TOTAL == 0 )); then
    printf "\nNo log files detected – nothing to do.\n"
    exit 0
fi

printf "\nTotal files across all locations: %d\n" "$TOTAL"

# 2️⃣ Dry‑run output – just show what would be deleted
if $DRY_RUN; then
    printf "\n--- Dry‑run preview (no files will be touched) ---\n"
    for p in "${LOG_PATHS[@]}"; do
        dir=$(expand_path "$p")
        if path_exists "$dir"; then
            cnt=$(file_count "$dir")
            if (( cnt > 0 )); then
                printf "\nDirectory: %s (%d files)\n" "$dir" "$cnt"
                list_sample "$dir"
                (( cnt > 20 )) && printf "  ... and %d more files\n" $((cnt-20))
            fi
        fi
    done
    printf "\nRun with 'confirm' to actually delete (with backup).\n"
    exit 0
fi

# 3️⃣ Confirm mode – make a backup before deleting
printf "\n--- Confirm mode – backup & delete ---\n"
mkdir -p "$BACKUP_DIR"

for p in "${LOG_PATHS[@]}"; do
    src=$(expand_path "$p")
    if path_exists "$src"; then
        cnt=$(file_count "$src")
        if (( cnt == 0 )); then
            printf "Skipping empty directory: %s\n" "$src"
            continue
        fi
        # Preserve relative structure inside backup dir
        rel=$(realpath --relative-to="$HOME" "$src")
        dest="$BACKUP_DIR/$rel"
        mkdir -p "$(dirname "$dest")"
        printf "Backing up %d files from %s to %s\n" "$cnt" "$src" "$dest"
        cp -a "$src" "$dest"
    else
        printf "Directory not present (skipping): %s\n" "$src"
    fi
done

# 4️⃣ Deletion – user must press ENTER to proceed for each dir
printf "\nBackup completed at %s\n" "$BACKUP_DIR"
printf "Review the backup if you need to restore any files.\n"

for p in "${LOG_PATHS[@]}"; do
    src=$(expand_path "$p")
    if path_exists "$src"; then
        cnt=$(file_count "$src")
        (( cnt == 0 )) && continue
        printf "\nDelete %d files in %s? [y/N] " "$cnt" "$src"
        read -r answer
        if [[ $answer =~ ^[Yy]$ ]]; then
            rm -rf "$src"/*
            printf "  → Deleted.\n"
        else
            printf "  → Skipped.\n"
        fi
    fi
done

# 5️⃣ Final verification
printf "\n--- Verification after cleanup ---\n"
for p in "${LOG_PATHS[@]}"; do
    dir=$(expand_path "$p")
    if path_exists "$dir"; then
        cnt=$(file_count "$dir")
        printf "%s – %d files remaining\n" "$dir" "$cnt"
    fi
done

printf "\nCleanup script finished.\n"
