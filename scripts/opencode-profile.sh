#!/usr/bin/env bash
# opencode-profile.sh - Full config profile switcher for OpenCode CLI
#
# Manages complete OpenCode configurations including providers, models,
# permissions, and mode-based agent routing. Each profile is an isolated
# directory with its own opencode.json and auth.json.
#
# Usage:
#   opencode-profile.sh list                        List all profiles
#   opencode-profile.sh create <name>               Create profile from current config
#   opencode-profile.sh switch <name>               Switch to a profile
#   opencode-profile.sh delete <name>               Delete a profile
#   opencode-profile.sh current                     Show active profile
#   opencode-profile.sh edit <name>                 Edit profile config in $EDITOR
#   opencode-profile.sh validate <name>             Validate profile JSON
#
# Examples:
#   opencode-profile.sh create work
#   opencode-profile.sh switch personal
#   DRY_RUN=1 opencode-profile.sh switch work   # Preview switch

set -euo pipefail

# OpenCode config locations (search order: global XDG → global home → project)
OPENCODE_CONFIG_DIR="${HOME}/.config/opencode"
OPENCODE_GLOBAL_CONFIG="${HOME}/.opencode.json"
PROFILES_DIR="${OPENCODE_CONFIG_DIR}/profiles"
AUTH_DIR="${HOME}/.local/share/opencode"

# ─── Helpers ──────────────────────────────────────────────────────────────────

# Get configured editor
_get_editor() {
    echo "${EDITOR:-${VISUAL:-nano}}"
}

# Validate JSON syntax (python3 or jq)
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

# Dry-run wrapper
_dry_run() {
    if [ "${DRY_RUN:-0}" = "1" ]; then
        echo "🔍 [DRY RUN] Would execute: $*"
        return 0
    else
        "$@"
    fi
}

# Backup auth with timestamp
_backup_auth() {
    if [ -f "$AUTH_DIR/auth.json" ]; then
        local timestamp
        timestamp=$(date +%Y%m%d_%H%M%S)
        local backup="$AUTH_DIR/auth.json.backup_${timestamp}"
        cp "$AUTH_DIR/auth.json" "$backup"
        chmod 600 "$backup"
        echo "  ✓ Auth backed up to: auth.json.backup_${timestamp}"
    fi
}

# Parse model string from opencode.json
_parse_model() {
    local file="$1"
    if command -v python3 &>/dev/null; then
        python3 -c "
import json, sys
try:
    cfg = json.load(open(sys.argv[1]))
    model = cfg.get('model', 'not set')
    small = cfg.get('small_model', '')
    if small:
        print(f'{model} (+ small: {small})')
    else:
        print(model)
except Exception as e:
    print(f'(parse error: {e})')
" "$file" 2>/dev/null || echo "(parse error)"
    elif command -v jq &>/dev/null; then
        local model small
        model=$(jq -r '.model // "not set"' "$file" 2>/dev/null)
        small=$(jq -r '.small_model // ""' "$file" 2>/dev/null)
        if [ -n "$small" ] && [ "$small" != "null" ]; then
            echo "$model (+ small: $small)"
        else
            echo "$model"
        fi
    else
        echo "(no parser available)"
    fi
}

# Parse enabled providers from opencode.json
_parse_providers() {
    local file="$1"
    if command -v python3 &>/dev/null; then
        python3 -c "
import json, sys
try:
    cfg = json.load(open(sys.argv[1]))
    providers = list(cfg.get('provider', {}).keys())
    disabled = cfg.get('disabled_providers', [])
    enabled = cfg.get('enabled_providers', providers)
    active = [p for p in enabled if p not in disabled]
    print(','.join(active) if active else 'none')
except:
    print('unknown')
" "$file" 2>/dev/null || echo "unknown"
    else
        echo "unknown"
    fi
}

# Parse mode configs from opencode.json
_parse_modes() {
    local file="$1"
    if command -v python3 &>/dev/null; then
        python3 -c "
import json, sys
try:
    cfg = json.load(open(sys.argv[1]))
    modes = cfg.get('mode', {})
    if modes:
        for name, mcfg in modes.items():
            model = mcfg.get('model', 'inherited')
            print(f'  {name}: {model}')
    else:
        print('  (no mode overrides)')
except:
    print('  (parse error)')
" "$file" 2>/dev/null || echo "  (parse error)"
    else
        echo "  (no parser available)"
    fi
}

# Find the active global config file
_find_active_config() {
    if [ -f "${OPENCODE_CONFIG_DIR}/opencode.json" ]; then
        echo "${OPENCODE_CONFIG_DIR}/opencode.json"
    elif [ -f "${OPENCODE_CONFIG_DIR}/.opencode.json" ]; then
        echo "${OPENCODE_CONFIG_DIR}/.opencode.json"
    elif [ -f "$OPENCODE_GLOBAL_CONFIG" ]; then
        echo "$OPENCODE_GLOBAL_CONFIG"
    else
        echo ""
    fi
}

# ─── Usage ────────────────────────────────────────────────────────────────────

usage() {
    cat << 'USAGE'
OpenCode CLI Profile Manager (Full Config Rotation)

Usage: opencode-profile.sh [list|switch|create|delete|current|edit|validate] [name]

Commands:
  list                  List all available profiles
  switch <profile>      Switch to a profile
  create <profile>      Create a new profile from current config
  delete <profile>      Delete a profile
  current               Show current active profile
  edit <profile>        Edit profile config in $EDITOR
  validate <profile>    Validate profile config syntax

Flags:
  DRY_RUN=1             Preview actions without executing

Examples:
  opencode-profile.sh create work
  opencode-profile.sh switch personal
  opencode-profile.sh edit work             # Open in $EDITOR
  opencode-profile.sh validate work         # Check JSON syntax
  opencode-profile.sh list                  # Show all profiles
  DRY_RUN=1 opencode-profile.sh switch work # Preview switch

Config locations:
  Global:   ~/.config/opencode/opencode.json  (or ~/.opencode.json)
  Profiles: ~/.config/opencode/profiles/<name>/opencode.json
  Auth:     ~/.local/share/opencode/auth.json
USAGE
    exit 0
}

# ─── List Profiles ────────────────────────────────────────────────────────────

list_profiles() {
    if [ ! -d "$PROFILES_DIR" ]; then
        echo "No profiles found. Create one with: opencode-profile.sh create <name>"
        return
    fi

    local has_profiles=false
    echo "Available profiles:"
    echo ""

    for profile_dir in "$PROFILES_DIR"/*/; do
        [ -d "$profile_dir" ] || continue
        has_profiles=true
        local name
        name=$(basename "$profile_dir")

        # Active marker
        local marker=""
        if [ -f "$OPENCODE_CONFIG_DIR/.active_profile" ] && \
           [ "$(cat "$OPENCODE_CONFIG_DIR/.active_profile")" = "$name" ]; then
            marker=" ✓"
        fi

        # Show config details
        local config_file="$profile_dir/opencode.json"
        if [ -f "$config_file" ]; then
            local model providers
            model=$(_parse_model "$config_file")
            providers=$(_parse_providers "$config_file")
            echo "  - ${name}${marker}"
            echo "      Model:     $model"
            echo "      Providers: $providers"

            # Show modes if any
            local modes
            modes=$(_parse_modes "$config_file")
            if [ -n "$modes" ] && [ "$modes" != "  (no mode overrides)" ]; then
                echo "      Modes:"
                echo "$modes"
            fi
        else
            echo "  - ${name}${marker}  (no opencode.json)"
        fi
    done

    if [ "$has_profiles" = false ]; then
        echo "No profiles found. Create one with: opencode-profile.sh create <name>"
    fi
}

# ─── Current Profile ──────────────────────────────────────────────────────────

current_profile() {
    if [ -n "${OPENCODE_PROFILE:-}" ]; then
        echo "Current profile (from env): $OPENCODE_PROFILE"
    elif [ -f "$OPENCODE_CONFIG_DIR/.active_profile" ]; then
        local active
        active=$(cat "$OPENCODE_CONFIG_DIR/.active_profile")
        echo "Current profile: $active"

        # Show its config if available
        local config_file="$PROFILES_DIR/$active/opencode.json"
        if [ -f "$config_file" ]; then
            echo ""
            echo "  Model:     $(_parse_model "$config_file")"
            echo "  Providers: $(_parse_providers "$config_file")"
        fi
    else
        echo "No profile selected. Using global config."
        local global_config
        global_config=$(_find_active_config)
        if [ -n "$global_config" ] && [ -f "$global_config" ]; then
            echo ""
            echo "  Active config: $global_config"
            echo "  Model:     $(_parse_model "$global_config")"
        fi
    fi
}

# ─── Switch Profile ───────────────────────────────────────────────────────────

switch_profile() {
    local profile="$1"

    if [ ! -d "$PROFILES_DIR/$profile" ]; then
        echo "❌ Error: Profile '$profile' not found."
        echo "Create it with: opencode-profile.sh create $profile"
        exit 1
    fi

    # Validate config before switching
    local config_file="$PROFILES_DIR/$profile/opencode.json"
    if [ -f "$config_file" ]; then
        if ! _validate_json "$config_file"; then
            echo "❌ Error: Profile config has invalid JSON syntax."
            echo "File: $config_file"
            echo "Fix the config or edit with: opencode-profile.sh edit $profile"
            exit 1
        fi
    fi

    # Determine target config location
    local target_config
    target_config=$(_find_active_config)
    if [ -z "$target_config" ]; then
        # No existing config — create one
        target_config="${OPENCODE_CONFIG_DIR}/opencode.json"
        mkdir -p "$OPENCODE_CONFIG_DIR"
    fi

    # Backup current config
    if [ -f "$target_config" ]; then
        cp "$target_config" "${target_config}.bak"
    fi

    # Restore profile config
    if [ -f "$config_file" ]; then
        _dry_run cp "$config_file" "$target_config"
        echo "✓ Restored config to: $target_config"
    else
        echo "⚠ Warning: No opencode.json in profile '$profile'"
    fi

    # Backup current auth before overwriting
    if [ -f "$PROFILES_DIR/$profile/auth.json" ]; then
        _backup_auth
        mkdir -p "$AUTH_DIR"
        _dry_run cp "$PROFILES_DIR/$profile/auth.json" "$AUTH_DIR/auth.json"
        chmod 600 "$AUTH_DIR/auth.json"
        echo "✓ Restored auth credentials"
    fi

    # Save active profile marker
    if [ "${DRY_RUN:-0}" = "1" ]; then
        echo ""
        echo "🔍 [DRY RUN] Would switch to profile: $profile"
        echo "Remove DRY_RUN=1 to execute."
    else
        echo "$profile" > "$OPENCODE_CONFIG_DIR/.active_profile"
        echo ""
        echo "✅ Switched to profile: $profile"
        echo ""
        echo "  Config: $target_config"
        echo "  Model:  $(_parse_model "$config_file")"
        echo ""
        echo "Start OpenCode with: opencode"
    fi
}

# ─── Create Profile ───────────────────────────────────────────────────────────

create_profile() {
    local profile="${1:-}"

    if [ -z "$profile" ]; then
        echo "❌ Error: Profile name required."
        echo "Usage: opencode-profile.sh create <name>"
        exit 1
    fi

    if [[ ! "$profile" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo "❌ Error: Profile name can only contain letters, numbers, hyphens, and underscores."
        exit 1
    fi

    mkdir -p "$PROFILES_DIR/$profile"

    # Find and save current config
    local current_config
    current_config=$(_find_active_config)
    if [ -n "$current_config" ] && [ -f "$current_config" ]; then
        cp "$current_config" "$PROFILES_DIR/$profile/opencode.json"
        echo "✓ Saved current config to profile"
    else
        cat > "$PROFILES_DIR/$profile/opencode.json" << 'EOF'
{
  "$schema": "https://opencode.ai/config.json",
  "model": "anthropic/claude-sonnet-4-20250514",
  "provider": {
    "anthropic": {
      "options": {}
    }
  }
}
EOF
        echo "⚠ No current config found. Created default config."
    fi

    # Save current auth if exists
    if [ -f "$AUTH_DIR/auth.json" ]; then
        cp "$AUTH_DIR/auth.json" "$PROFILES_DIR/$profile/auth.json"
        chmod 600 "$PROFILES_DIR/$profile/auth.json"
        echo "✓ Saved current auth credentials"
    fi

    echo ""
    echo "✅ Created profile: $profile"
    echo "Config location: $PROFILES_DIR/$profile/opencode.json"
    echo ""
    local editor
    editor=$(_get_editor)
    echo "Edit the config file, then switch to it:"
    echo "  $editor $PROFILES_DIR/$profile/opencode.json"
    echo "  opencode-profile.sh switch $profile"
}

# ─── Edit Profile ─────────────────────────────────────────────────────────────

edit_profile() {
    local profile="${1:-}"
    local config_file="$PROFILES_DIR/$profile/opencode.json"

    if [ ! -d "$PROFILES_DIR/$profile" ]; then
        echo "❌ Error: Profile '$profile' not found."
        echo "Create it with: opencode-profile.sh create $profile"
        exit 1
    fi

    if [ ! -f "$config_file" ]; then
        echo "⚠ No config file yet. Creating default..."
        cat > "$config_file" << 'EOF'
{
  "$schema": "https://opencode.ai/config.json",
  "model": "anthropic/claude-sonnet-4-20250514",
  "provider": {
    "anthropic": {
      "options": {}
    }
  }
}
EOF
    fi

    local editor
    editor=$(_get_editor)

    echo "Opening $config_file in $editor..."
    "$editor" "$config_file"

    echo ""
    if _validate_json "$config_file"; then
        echo "✅ Config saved and validated."
        echo ""
        echo "  Model:     $(_parse_model "$config_file")"
        echo "  Providers: $(_parse_providers "$config_file")"
    else
        echo "❌ Config has invalid JSON syntax. Please fix before switching."
    fi
}

# ─── Validate Profile ─────────────────────────────────────────────────────────

validate_profile() {
    local profile="${1:-}"
    local config_file="$PROFILES_DIR/$profile/opencode.json"

    if [ ! -d "$PROFILES_DIR/$profile" ]; then
        echo "❌ Error: Profile '$profile' not found."
        exit 1
    fi

    if [ ! -f "$config_file" ]; then
        echo "⚠ No config file in profile '$profile'."
        exit 1
    fi

    echo "Validating profile: $profile"
    echo "File: $config_file"
    echo "---"

    if _validate_json "$config_file"; then
        echo "---"
        echo "✅ Config syntax is valid."
        echo ""
        echo "  Model:     $(_parse_model "$config_file")"
        echo "  Providers: $(_parse_providers "$config_file")"
        echo "  Modes:"
        _parse_modes "$config_file"
    else
        echo "❌ Config has invalid JSON syntax."
        exit 1
    fi
}

# ─── Delete Profile ───────────────────────────────────────────────────────────

delete_profile() {
    local profile="${1:-}"

    if [ -z "$profile" ]; then
        echo "❌ Error: Profile name required."
        exit 1
    fi

    if [ ! -d "$PROFILES_DIR/$profile" ]; then
        echo "❌ Error: Profile '$profile' not found."
        exit 1
    fi

    read -r -p "Delete profile '$profile'? This cannot be undone. [y/N] " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        rm -rf "$PROFILES_DIR/$profile"

        # Clear active profile if it was the deleted one
        if [ -f "$OPENCODE_CONFIG_DIR/.active_profile" ] && \
           [ "$(cat "$OPENCODE_CONFIG_DIR/.active_profile")" = "$profile" ]; then
            rm "$OPENCODE_CONFIG_DIR/.active_profile"
            echo "✓ Cleared active profile"
        fi

        echo "✅ Deleted profile: $profile"
    else
        echo "Cancelled."
    fi
}

# ─── Main ─────────────────────────────────────────────────────────────────────

case "${1:-}" in
    list)
        list_profiles
        ;;
    switch)
        if [ -z "${2:-}" ]; then
            echo "❌ Error: Profile name required."
            echo "Usage: opencode-profile.sh switch <name>"
            exit 1
        fi
        switch_profile "$2"
        ;;
    create)
        create_profile "${2:-}"
        ;;
    delete)
        delete_profile "${2:-}"
        ;;
    current)
        current_profile
        ;;
    edit)
        edit_profile "${2:-}"
        ;;
    validate)
        validate_profile "${2:-}"
        ;;
    *)
        usage
        ;;
esac
