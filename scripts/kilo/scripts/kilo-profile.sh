#!/usr/bin/env bash
# kilo-profile.sh - Switch between Kilo CLI account profiles
# 
# Usage:
#   kilo-profile.sh list                  List all available profiles
#   kilo-profile.sh switch <profile>      Switch to a profile
#   kilo-profile.sh create <profile>      Create a new profile from current config
#   kilo-profile.sh delete <profile>      Delete a profile
#   kilo-profile.sh current               Show current active profile
#
# Examples:
#   kilo-profile.sh create work
#   kilo-profile.sh switch personal
#   kilo-profile.sh list

set -euo pipefail

KILO_CONFIG_DIR="${HOME}/.config/kilo"
PROFILES_DIR="${KILO_CONFIG_DIR}/profiles"
AUTH_DIR="${HOME}/.local/share/kilo"

# Helper: get configured editor
_get_editor() {
    echo "${EDITOR:-${VISUAL:-nano}}"
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
        # No validator available — skip validation
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

# Helper: backup auth with timestamp
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

usage() {
    echo "Kilo CLI Profile Manager (Config Directory Rotation)"
    echo ""
    echo "Usage: kilo-profile.sh [list|switch|create|delete|current|edit|validate] [profile-name]"
    echo ""
    echo "Commands:"
    echo "  list                  List all available profiles"
    echo "  switch <profile>      Switch to a profile"
    echo "  create <profile>      Create a new profile from current config"
    echo "  delete <profile>      Delete a profile"
    echo "  current               Show current active profile"
    echo "  edit <profile>        Edit profile config in \$EDITOR"
    echo "  validate <profile>    Validate profile config syntax"
    echo ""
    echo "Flags:"
    echo "  --dry-run             Preview actions without executing"
    echo "  DRY_RUN=1             Environment variable for dry-run"
    echo ""
    echo "Examples:"
    echo "  kilo-profile.sh create work"
    echo "  kilo-profile.sh switch personal"
    echo "  kilo-profile.sh edit work             # Open in \$EDITOR"
    echo "  kilo-profile.sh validate work         # Check JSON syntax"
    echo "  DRY_RUN=1 kilo-profile.sh switch work # Preview switch"
    exit 1
}

list_profiles() {
    if [ ! -d "$PROFILES_DIR" ]; then
        echo "No profiles found. Create one with: kilo-profile.sh create <name>"
        return
    fi

    local has_profiles=false
    echo "Available profiles:"
    echo ""
    for profile in "$PROFILES_DIR"/*/; do
        if [ -d "$profile" ]; then
            has_profiles=true
            name=$(basename "$profile")
            marker=""
            if [ -f "$KILO_CONFIG_DIR/.active_profile" ] && \
               [ "$(cat "$KILO_CONFIG_DIR/.active_profile")" = "$name" ]; then
                marker=" ✓"
            fi

            # Show model/provider if config exists
            local info=""
            if [ -f "$profile/opencode.json" ]; then
                if command -v python3 &>/dev/null; then
                    info=$(python3 -c "
import json
try:
    cfg = json.load(open('$profile/opencode.json'))
    model = cfg.get('model', 'not set')
    print(model)
except:
    print('(parse error)')
" 2>/dev/null || echo "(parse error)")
                fi
            fi

            if [ -n "$info" ]; then
                echo "  - ${name}${marker}  ($info)"
            else
                echo "  - ${name}${marker}"
            fi
        fi
    done

    if [ "$has_profiles" = false ]; then
        echo "No profiles found. Create one with: kilo-profile.sh create <name>"
    fi
}

current_profile() {
    if [ -n "${KILO_PROFILE:-}" ]; then
        echo "Current profile (from env): $KILO_PROFILE"
    elif [ -f "$KILO_CONFIG_DIR/.active_profile" ]; then
        local active
        active=$(cat "$KILO_CONFIG_DIR/.active_profile")
        echo "Current profile: $active"
    else
        echo "No profile selected. Using default config."
    fi
}

switch_profile() {
    local profile=$1

    if [ ! -d "$PROFILES_DIR/$profile" ]; then
        echo "❌ Error: Profile '$profile' not found."
        echo "Create it with: kilo-profile.sh create $profile"
        exit 1
    fi

    # Validate config before switching
    local config_file="$PROFILES_DIR/$profile/opencode.json"
    if [ -f "$config_file" ]; then
        if ! _validate_json "$config_file"; then
            echo "❌ Error: Profile config has invalid JSON syntax."
            echo "File: $config_file"
            echo "Fix the config or edit with: kilo-profile.sh edit $profile"
            exit 1
        fi
    fi

    # Backup current config
    if [ -f "$KILO_CONFIG_DIR/opencode.json" ]; then
        cp "$KILO_CONFIG_DIR/opencode.json" "$KILO_CONFIG_DIR/opencode.json.bak"
    fi

    # Restore profile config
    if [ -f "$config_file" ]; then
        _dry_run cp "$config_file" "$KILO_CONFIG_DIR/opencode.json"
        echo "✓ Restored config from profile: $profile"
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

    # Save active profile
    _dry_run bash -c "echo '$profile' > '$KILO_CONFIG_DIR/.active_profile'"

    if [ "${DRY_RUN:-0}" = "1" ]; then
        echo ""
        echo "🔍 [DRY RUN] Would switch to profile: $profile"
        echo "Remove DRY_RUN=1 to execute."
    else
        echo "$profile" > "$KILO_CONFIG_DIR/.active_profile"
        echo ""
        echo "✅ Switched to profile: $profile"
        echo "Start Kilo with: kilo"
    fi
}

create_profile() {
    local profile=$1

    if [ -z "$profile" ]; then
        echo "❌ Error: Profile name required."
        echo "Usage: kilo-profile.sh create <name>"
        exit 1
    fi

    # Validate profile name
    if [[ ! "$profile" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo "❌ Error: Profile name can only contain letters, numbers, hyphens, and underscores."
        exit 1
    fi

    # Create profiles directory
    mkdir -p "$PROFILES_DIR/$profile"

    # Save current config
    if [ -f "$KILO_CONFIG_DIR/opencode.json" ]; then
        cp "$KILO_CONFIG_DIR/opencode.json" "$PROFILES_DIR/$profile/opencode.json"
        echo "✓ Saved current config to profile"
    else
        echo '{}' > "$PROFILES_DIR/$profile/opencode.json"
        echo "⚠ No current config found. Created empty config."
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
    echo "  kilo-profile.sh switch $profile"
}

edit_profile() {
    local profile=$1
    local config_file="$PROFILES_DIR/$profile/opencode.json"

    if [ ! -d "$PROFILES_DIR/$profile" ]; then
        echo "❌ Error: Profile '$profile' not found."
        echo "Create it with: kilo-profile.sh create $profile"
        exit 1
    fi

    if [ ! -f "$config_file" ]; then
        echo "⚠ No config file yet. Creating empty one..."
        echo '{}' > "$config_file"
    fi

    local editor
    editor=$(_get_editor)

    echo "Opening $config_file in $editor..."
    "$editor" "$config_file"

    # Validate after edit
    echo ""
    if _validate_json "$config_file"; then
        echo "✅ Config saved and validated."
    else
        echo "❌ Config has invalid JSON syntax. Please fix before switching."
    fi
}

validate_profile() {
    local profile=$1
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
        echo "✅ Config syntax is valid."
    else
        echo "❌ Config has invalid JSON syntax."
        exit 1
    fi
}

delete_profile() {
    local profile=$1
    
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
        if [ -f "$KILO_CONFIG_DIR/.active_profile" ] && \
           [ "$(cat "$KILO_CONFIG_DIR/.active_profile")" = "$profile" ]; then
            rm "$KILO_CONFIG_DIR/.active_profile"
            echo "✓ Cleared active profile"
        fi
        
        echo "✅ Deleted profile: $profile"
    else
        echo "Cancelled."
    fi
}

# Main command handler
case "${1:-}" in
    list)
        list_profiles
        ;;
    switch)
        if [ -z "${2:-}" ]; then
            echo "❌ Error: Profile name required."
            echo "Usage: kilo-profile.sh switch <name>"
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
