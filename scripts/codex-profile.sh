#!/usr/bin/env bash
# codex-profile.sh - Full config profile switcher for OpenAI Codex CLI
#
# Manages complete Codex configurations including providers, models,
# sandbox settings, and MCP servers. Each profile is an isolated config.
#
# Usage:
#   codex-profile.sh list                        List all profiles
#   codex-profile.sh create <name>               Create profile from current config
#   codex-profile.sh switch <name>               Switch to a profile
#   codex-profile.sh delete <name>               Delete a profile
#   codex-profile.sh current                     Show active profile
#   codex-profile.sh edit <name>                 Edit profile config in $EDITOR
#   codex-profile.sh validate <name>             Validate profile TOML
#
# Examples:
#   codex-profile.sh create work
#   codex-profile.sh switch personal
#   DRY_RUN=1 codex-profile.sh switch work   # Preview switch

set -euo pipefail

CODEX_HOME="${CODEX_HOME:-${HOME}/.codex}"
CODEX_CONFIG="${CODEX_HOME}/config.toml"
CODEX_AUTH="${CODEX_HOME}/auth.json"
PROFILES_DIR="${CODEX_HOME}/profiles"

_get_editor() {
    echo "${EDITOR:-${VISUAL:-nano}}"
}

_validate_toml() {
    local file="$1"
    if command -v python3 &>/dev/null; then
        if ! python3 -c 'import toml; toml.load(open(sys.argv[1]))' "$file" 2>/dev/null; then
            return 1
        fi
    elif command -v toml &>/dev/null; then
        if ! toml validate "$file" 2>/dev/null; then
            return 1
        fi
    fi
    return 0
}

_dry_run() {
    if [ "${DRY_RUN:-0}" = "1" ]; then
        echo "🔍 [DRY RUN] Would execute: $*"
        return 0
    else
        "$@"
    fi
}

_backup_config() {
    if [ -f "$CODEX_CONFIG" ]; then
        local timestamp
        timestamp=$(date +%Y%m%d_%H%M%S)
        local backup="$CODEX_CONFIG.backup_${timestamp}"
        cp "$CODEX_CONFIG" "$backup"
        chmod 600 "$backup"
        echo "  ✓ Config backed up to: config.toml.backup_${timestamp}"
    fi
}

_backup_auth() {
    if [ -f "$CODEX_AUTH" ]; then
        local timestamp
        timestamp=$(date +%Y%m%d_%H%M%S)
        local backup="$CODEX_AUTH.backup_${timestamp}"
        cp "$CODEX_AUTH" "$backup"
        chmod 600 "$backup"
        echo "  ✓ Auth backed up to: auth.json.backup_${timestamp}"
    fi
}

_parse_model() {
    local file="$1"
    if command -v python3 &>/dev/null; then
        python3 -c "
import sys, toml
try:
    cfg = toml.load(open(sys.argv[1]))
    model = cfg.get('model', 'not set')
    print(model)
except Exception as e:
    print(f'(parse error: {e})')
" "$file" 2>/dev/null || echo "(parse error)"
    else
        grep -E '^model\s*=' "$file" 2>/dev/null | head -1 | cut -d'=' -f2- | tr -d ' "'
    fi
}

usage() {
    cat << 'USAGE'
Codex CLI — Profile Manager

Usage: codex-profile.sh <command> [arguments]

Commands:
  list                  List available profiles
  create <name>         Create profile from current config
  switch <name>         Switch to a profile
  delete <name>         Delete a profile
  current               Show active profile
  edit <name>           Edit profile config in $EDITOR
  validate <name>       Validate profile TOML

Profiles directory: ~/.codex/profiles

Examples:
  codex-profile.sh create work
  codex-profile.sh switch personal
  codex-profile.sh list
  DRY_RUN=1 codex-profile.sh switch work

Notes:
  - Profiles store complete config.toml + auth.json
  - Switching profiles backs up current config first
  - Use DRY_RUN=1 to preview switch without executing
USAGE
    exit 0
}

list_profiles() {
    if [ ! -d "$PROFILES_DIR" ]; then
        echo "No profiles found."
        echo "Create one with: codex-profile.sh create <name>"
        return
    fi

    local has_profiles=false
    echo "Available profiles:"
    echo ""

    local current_profile=""
    if [ -f "${CODEX_HOME}/.active_profile" ]; then
        current_profile=$(cat "${CODEX_HOME}/.active_profile")
    fi

    shopt -s nullglob 2>/dev/null || true
    local dirs=("$PROFILES_DIR"/*/)
    shopt -u nullglob 2>/dev/null || true

    for dir in "${dirs[@]}"; do
        [ -d "$dir" ] || continue
        has_profiles=true
        local name
        name=$(basename "$dir")

        local marker=""
        if [ -n "$current_profile" ] && [ "$current_profile" = "$name" ]; then
            marker=" ✓ (active)"
        fi

        local config="$dir/config.toml"
        local model=""
        if [ -f "$config" ]; then
            model=$(_parse_model "$config")
        fi

        if [ -n "$model" ]; then
            echo "  • ${name}${marker}  (model: $model)"
        else
            echo "  • ${name}${marker}"
        fi
    done

    if [ "$has_profiles" = false ]; then
        echo "No profiles found."
        echo "Create one with: codex-profile.sh create <name>"
    fi

    echo ""
    echo "Profiles directory: $PROFILES_DIR"
}

create_profile() {
    local name="${1:-}"

    if [ -z "$name" ]; then
        echo "❌ Error: Profile name required."
        echo "Usage: codex-profile.sh create <name>"
        exit 1
    fi

    if [[ ! "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo "❌ Error: Profile name can only contain letters, numbers, hyphens, and underscores."
        exit 1
    fi

    mkdir -p "$PROFILES_DIR/$name"

    local profile_config="$PROFILES_DIR/$name/config.toml"
    local profile_auth="$PROFILES_DIR/$name/auth.json"

    if [ -f "$CODEX_CONFIG" ]; then
        cp "$CODEX_CONFIG" "$profile_config"
        chmod 600 "$profile_config"
        echo "  ✓ Config copied to: $profile_config"
    else
        cat > "$profile_config" << 'EOF'
# Codex CLI Profile Configuration
model = "gpt-5.4"
sandbox_mode = "read-only"
approval_mode = "full-auto"
EOF
        chmod 600 "$profile_config"
        echo "  ✓ Created default config: $profile_config"
    fi

    if [ -f "$CODEX_AUTH" ]; then
        cp "$CODEX_AUTH" "$profile_auth"
        chmod 600 "$profile_auth"
        echo "  ✓ Auth copied to: $profile_auth"
    fi

    echo ""
    echo "✅ Created profile: $name"
    echo "Profile directory: $PROFILES_DIR/$name"
}

switch_profile() {
    local name="${1:-}"

    if [ -z "$name" ]; then
        echo "❌ Error: Profile name required."
        echo "Usage: codex-profile.sh switch <name>"
        exit 1
    fi

    local profile_dir="$PROFILES_DIR/$name"
    local profile_config="$profile_dir/config.toml"
    local profile_auth="$profile_dir/auth.json"

    if [ ! -d "$profile_dir" ]; then
        echo "❌ Error: Profile '$name' not found."
        echo "Available profiles:"
        list_profiles
        exit 1
    fi

    if [ ! -f "$profile_config" ]; then
        echo "❌ Error: Profile config not found at $profile_config"
        exit 1
    fi

    _dry_run _backup_config
    _dry_run _backup_auth

    if [ -f "$profile_config" ]; then
        _dry_run cp "$profile_config" "$CODEX_CONFIG"
        _dry_run chmod 600 "$CODEX_CONFIG"
        echo "  ✓ Config activated: $CODEX_CONFIG"
    fi

    if [ -f "$profile_auth" ]; then
        _dry_run cp "$profile_auth" "$CODEX_AUTH"
        _dry_run chmod 600 "$CODEX_AUTH"
        echo "  ✓ Auth activated: $CODEX_AUTH"
    fi

    _dry_run echo "$name" > "${CODEX_HOME}/.active_profile"

    echo ""
    echo "✅ Switched to profile: $name"
}

delete_profile() {
    local name="${1:-}"

    if [ -z "$name" ]; then
        echo "❌ Error: Profile name required."
        echo "Usage: codex-profile.sh delete <name>"
        exit 1
    fi

    local profile_dir="$PROFILES_DIR/$name"

    if [ ! -d "$profile_dir" ]; then
        echo "❌ Error: Profile '$name' not found."
        exit 1
    fi

    local current=""
    if [ -f "${CODEX_HOME}/.active_profile" ]; then
        current=$(cat "${CODEX_HOME}/.active_profile")
    fi

    if [ -n "$current" ] && [ "$current" = "$name" ]; then
        echo "❌ Error: Cannot delete active profile. Switch to another first."
        exit 1
    fi

    echo "Deleting profile: $name"
    echo "Directory: $profile_dir"
    echo ""
    read -p "Are you sure? (y/N) " -n 1 -r reply
    echo
    if [[ ! $reply =~ ^[Yy]$ ]]; then
        echo "Cancelled."
        exit 0
    fi

    rm -rf "$profile_dir"
    echo "✅ Deleted profile: $name"
}

show_current() {
    local current=""
    if [ -f "${CODEX_HOME}/.active_profile" ]; then
        current=$(cat "${CODEX_HOME}/.active_profile")
    fi

    if [ -n "$current" ]; then
        echo "Active profile: $current"
    else
        echo "No active profile (using default config)"
    fi

    if [ -f "$CODEX_CONFIG" ]; then
        echo ""
        echo "Current config:"
        local model sandbox approval
        model=$(_parse_model "$CODEX_CONFIG")
        sandbox=$(grep -E '^sandbox_mode\s*=' "$CODEX_CONFIG" 2>/dev/null | cut -d'=' -f2- | tr -d ' "' || echo "default")
        approval=$(grep -E '^approval_mode\s*=' "$CODEX_CONFIG" 2>/dev/null | cut -d'=' -f2- | tr -d ' "' || echo "default")
        echo "  Model: $model"
        echo "  Sandbox: $sandbox"
        echo "  Approval: $approval"
    fi
}

edit_profile() {
    local name="${1:-}"

    if [ -z "$name" ]; then
        echo "❌ Error: Profile name required."
        exit 1
    fi

    local profile_dir="$PROFILES_DIR/$name"
    local profile_config="$profile_dir/config.toml"

    if [ ! -d "$profile_dir" ]; then
        echo "❌ Error: Profile '$name' not found."
        exit 1
    fi

    if [ ! -f "$profile_config" ]; then
        echo "❌ Error: Profile config not found at $profile_config"
        exit 1
    fi

    local editor
    editor=$(_get_editor)

    echo "Opening $profile_config in $editor..."
    "$editor" "$profile_config"

    echo ""
    if _validate_toml "$profile_config"; then
        echo "✅ Config saved and validated."
    else
        echo "⚠ Config saved but has validation warnings."
    fi
}

validate_profile() {
    local name="${1:-}"

    if [ -z "$name" ]; then
        echo "❌ Error: Profile name required."
        exit 1
    fi

    local profile_dir="$PROFILES_DIR/$name"
    local profile_config="$profile_dir/config.toml"

    if [ ! -d "$profile_dir" ]; then
        echo "❌ Error: Profile '$name' not found."
        exit 1
    fi

    if [ ! -f "$profile_config" ]; then
        echo "❌ Error: Profile config not found at $profile_config"
        exit 1
    fi

    echo "Validating: $name"
    echo "File: $profile_config"
    echo "---"

    if _validate_toml "$profile_config"; then
        echo "---"
        echo "✅ Config TOML is valid."
    else
        echo "---"
        echo "❌ Config has validation errors."
        exit 1
    fi
}

case "${1:-}" in
    list)
        list_profiles
        ;;
    create)
        create_profile "${2:-}"
        ;;
    switch)
        switch_profile "${2:-}"
        ;;
    delete)
        delete_profile "${2:-}"
        ;;
    current)
        show_current
        ;;
    edit)
        edit_profile "${2:-}"
        ;;
    validate)
        validate_profile "${2:-}"
        ;;
    ""|--help|-h|help)
        usage
        ;;
    *)
        echo "❌ Unknown command: $1"
        echo ""
        usage
        ;;
esac
