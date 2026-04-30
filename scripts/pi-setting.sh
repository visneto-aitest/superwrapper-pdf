#!/usr/bin/env bash
# pi-setting.sh – Manage Pi coding‑agent configuration, skills and backups
#
# Features:
#   1) List current settings (config files, installed skills, env vars)
#   2) Create a dated tar.gz backup of all settings
#   3) Restore settings from a backup archive
#   4) Interactive configuration menu (set values, toggle options, manage skills)
#
# Requirements:
#   - Bash 4+
#   - Standard GNU tools (tar, gzip, grep, sed, awk, mkdir, rm, readlink)

set -euo pipefail
IFS=$'\n\t'

# -------------------- Constants & Helpers --------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="${HOME}/.pi-agent"
CONFIG_DIR="${BASE_DIR}/config"
SKILLS_DIR="${BASE_DIR}/skills"
BACKUP_DIR="${BASE_DIR}/backups"
ENV_FILE="${BASE_DIR}/env.sh"

mkdir -p "${CONFIG_DIR}" "${SKILLS_DIR}" "${BACKUP_DIR}"

log()   { echo "[${1^^}] $2"; }
error() { log error "$1" >&2; }
info()  { log info "$1"; }

# Resolve a path that may contain ~ or relative components
resolve_path() {
    local p="$1"
    [[ "$p" == ~* ]] && p="${HOME}${p:1}"
    echo "$(cd "$(dirname "$p")" && pwd)/$(basename "$p")"
}

# -------------------- 1) List Settings --------------------
list_settings() {
    echo "=== Pi Agent Settings ==="
    echo "Base directory: $BASE_DIR"
    echo
    echo "-- Config files (-- in $CONFIG_DIR):"
    find "$CONFIG_DIR" -type f -name "*.conf" -print | sed "s|^|  |"
    echo
    echo "-- Installed skills (-- in $SKILLS_DIR):"
    find "$SKILLS_DIR" -maxdepth 1 -type d ! -path "$SKILLS_DIR" -print | sed "s|^|  |"
    echo
    echo "-- Environment variables (-- loaded from $ENV_FILE):"
    if [[ -f "$ENV_FILE" ]]; then
        grep -E '^[A-Za-z_][A-Za-z0-9_]*=' "$ENV_FILE" | sed "s|^|  |"
    else
        echo "  (none)"
    fi
    echo "=== End of Listing ==="
}

# -------------------- 2) Backup Settings --------------------
backup_settings() {
    local timestamp
    timestamp=$(date +"%Y%m%d_%H%M%S")
    local archive="${BACKUP_DIR}/pi-settings_${timestamp}.tar.gz"

    tar -czf "$archive" -C "$BASE_DIR" config skills env.sh 2>/dev/null \
        && info "Backup created: $archive" \
        || error "Backup failed"
}

# -------------------- 3) Restore Settings --------------------
restore_settings() {
    local archive
    read -rp "Enter path to backup archive: " archive
    archive=$(resolve_path "$archive")
    [[ -f "$archive" ]] || { error "File not found: $archive"; return 1; }

    tar -xzf "$archive" -C "$BASE_DIR" 2>/dev/null \
        && info "Restored settings from $archive" \
        || error "Restore failed"
}

# -------------------- 4) Interactive Configuration --------------------
configure_menu() {
    while true; do
        echo
        echo "=== Pi Agent Configuration Menu ==="
        echo "1) Set/Update a config value"
        echo "2) Toggle a boolean option"
        echo "3) Install a new skill"
        echo "4) Remove an existing skill"
        echo "5) List current settings"
        echo "6) Back to main menu"
        read -rp "Choose an option [1-6]: " opt
        case "$opt" in
            1) set_config ;;
            2) toggle_option ;;
            3) install_skill ;;
            4) remove_skill ;;
            5) list_settings ;;
            6) break ;;
            *) error "Invalid choice" ;;
        esac
    done
}

set_config() {
    read -rp "Config file name (without .conf): " cf
    local path="${CONFIG_DIR}/${cf}.conf"
    read -rp "Enter key: " key
    read -rp "Enter value: " val
    if grep -q "^${key}=" "$path" 2>/dev/null; then
        sed -i.bak "s|^${key}=.*|${key}=${val}|" "$path"
    else
        echo "${key}=${val}" >>"$path"
    fi
    info "Set ${key} in $path"
}

toggle_option() {
    read -rp "Config file name (without .conf): " cf
    local path="${CONFIG_DIR}/${cf}.conf"
    read -rp "Enter key to toggle (true/false): " key
    if [[ -f "$path" ]]; then
        if grep -q "^${key}=true" "$path"; then
            sed -i.bak "s|^${key}=true|${key}=false|" "$path"
            info "Toggled ${key}=false"
        else
            sed -i.bak "s|^${key}=false|${key}=true|" "$path" || echo "${key}=true" >>"$path"
            info "Toggled ${key}=true"
        fi
    else
        echo "${key}=true" >"$path"
        info "Created $path with ${key}=true"
    fi
}

install_skill() {
    read -rp "Path or URL of skill to install: " src
    src=$(resolve_path "$src")
    [[ -d "$src" ]] || { error "Skill directory not found: $src"; return; }
    local name
    name=$(basename "$src")
    cp -r "$src" "${SKILLS_DIR}/${name}"
    info "Skill '${name}' installed."
}

remove_skill() {
    read -rp "Skill name to remove: " name
    local dir="${SKILLS_DIR}/${name}"
    [[ -d "$dir" ]] || { error "Skill not found: $name"; return; }
    rm -rf "$dir"
    info "Skill '${name}' removed."
}

# -------------------- Main Menu --------------------
main_menu() {
    while true; do
        echo
        echo "=== Pi Setting Utility ==="
        echo "1) List settings"
        echo "2) Backup settings"
        echo "3) Restore settings"
        echo "4) Configure settings (interactive)"
        echo "5) Show help"
        echo "6) Exit"
        read -rp "Select an option [1-6]: " choice
        case "$choice" in
            1) list_settings ;;
            2) backup_settings ;;
            3) restore_settings ;;
            4) configure_menu ;;
            5) usage ;;
            6) exit 0 ;;
            *) error "Invalid selection" ;;
        esac
    done
}

usage() {
    cat <<'EOF'
pi-setting.sh – Manage Pi coding‑agent configuration

Usage:
  ./pi-setting.sh          # launch interactive menu
  ./pi-setting.sh list     # list current settings
  ./pi-setting.sh backup   # create dated backup
  ./pi-setting.sh restore  # restore from backup (prompts for file)
  ./pi-setting.sh help     # display this help text

The script works with the existing pi‑skills.sh and pi_skills_combined.sh scripts,
relying on the same base directory (~/.pi-agent). All paths are resolved
correctly even when using "~".
EOF
}

# -------------------- Argument Parsing --------------------
if [[ "${#}" -gt 0 ]]; then
    case "$1" in
        list)   list_settings ;;
        backup) backup_settings ;;
        restore) restore_settings ;;
        help)   usage ;;
        *)      error "Unknown command: $1"; usage; exit 1 ;;
    esac
    exit 0
fi

# If no arguments, start interactive menu
main_menu
