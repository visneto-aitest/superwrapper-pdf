#!/usr/bin/env bash
# gemini-profile.sh - Full config profile switcher for Gemini CLI
#
# Manages complete Gemini CLI configurations including settings.json,
# .env files, and OAuth tokens. Each profile is an isolated directory.
#
# Usage:
#   gemini-profile.sh list                        List all profiles
#   gemini-profile.sh create <name>               Create profile from current config
#   gemini-profile.sh switch <name>               Switch to a profile
#   gemini-profile.sh delete <name>               Delete a profile
#   gemini-profile.sh current                     Show active profile
#   gemini-profile.sh edit <name>                 Edit settings.json in $EDITOR
#   gemini-profile.sh validate <name>             Validate profile JSON
#
# Examples:
#   gemini-profile.sh create work
#   gemini-profile.sh switch personal
#   DRY_RUN=1 gemini-profile.sh switch work   # Preview switch

set -euo pipefail

GEMINI_CONFIG_DIR="${HOME}/.gemini"
GEMINI_PROFILES_DIR="${GEMINI_CONFIG_DIR}/profiles"
GEMINI_ACTIVE_MARKER="${GEMINI_CONFIG_DIR}/.active-profile"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source shared library
if [ -f "$SCRIPT_DIR/../lib/common.sh" ]; then
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/../lib/common.sh"
else
    _get_editor() { printf '%s' "${EDITOR:-${VISUAL:-nano}}"; }
    _hash_string() { printf '%s' "$1" | shasum -a 256 2>/dev/null | cut -d' ' -f1 || printf '%s' "$1" | sha256sum 2>/dev/null | cut -d' ' -f1 || echo "unknown"; }
    _validate_json() { local f="$1"; if command -v python3 &>/dev/null; then python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$f" 2>/dev/null || return 1; elif command -v jq &>/dev/null; then jq empty "$f" 2>/dev/null || return 1; fi; return 0; }
    _dry_run() { if [ "${DRY_RUN:-0}" = "1" ]; then printf '🔍 [DRY RUN] Would execute: %s\n' "$*"; return 0; else "$@"; fi; }
    _backup_file() { local f="$1"; if [ -f "$f" ]; then local d b t; d=$(dirname "$f"); b=$(basename "$f"); t=$(date +%Y%m%d_%H%M%S); local bk="${d}/${b}.backup_${t}"; cp "$f" "$bk"; chmod 600 "$bk"; printf '  ✓ Backed up to: %s\n' "$(basename "$bk")"; fi; }
fi

# ─── Helpers ──────────────────────────────────────────────────────────────────

# Parse settings.json for Gemini CLI config details
_parse_settings() {
    local file="$1"
    if command -v python3 &>/dev/null; then
        python3 -c '
import json, sys
try:
    cfg = json.load(open(sys.argv[1]))
    # Extract key info
    model = cfg.get("model", cfg.get("defaultModel", "default"))
    auth = "oauth"
    if "apiKey" in cfg:
        auth = "api-key"
    elif "googleCloudProject" in cfg:
        auth = "workspace"
    temp = cfg.get("temperature", cfg.get("generationConfig", {}).get("temperature", "default"))
    print(f"{auth} | model: {model} | temp: {temp}")
except Exception as e:
    print(f"parse error: {e}")
' "$file" 2>/dev/null || echo "(parse error)"
    else
        echo "(no parser available)"
    fi
}

# List directory contents
_dir_summary() {
    local dir="$1"
    local label="$2"
    if [ -d "$dir" ]; then
        local count
        count=$(find "$dir" -maxdepth 1 -type f 2>/dev/null | wc -l | tr -d ' ')
        if [ "$count" -gt 0 ]; then
            printf '      %s: %s file(s)\n' "$label" "$count"
        fi
    fi
}

# ─── Usage ────────────────────────────────────────────────────────────────────

usage() {
    cat << 'USAGE'
Gemini CLI Profile Manager (Full Config Rotation)

Usage: gemini-profile.sh [list|switch|create|delete|current|edit|validate] [name]

Commands:
  list                  List all available profiles
  switch <profile>      Switch to a profile
  create <profile>      Create a new profile from current config
  delete <profile>      Delete a profile
  current               Show current active profile
  edit <profile>        Edit profile settings.json in $EDITOR
  validate <profile>    Validate profile JSON syntax

Flags:
  DRY_RUN=1             Preview actions without executing

How it works:
  Gemini CLI uses ~/.gemini/settings.json for configuration.
  This script rotates the entire ~/.gemini/ directory from isolated
  profile directories for complete account isolation.

Profile structure:
  ~/.gemini/profiles/
  └── <name>/
      ├── settings.json        # Gemini CLI settings
      ├── .env                 # API keys (if using API key mode)
      └── GEMINI.md            # Global instructions/context

Examples:
  gemini-profile.sh create work
  gemini-profile.sh switch personal
  gemini-profile.sh edit work              # Open in $EDITOR
  gemini-profile.sh validate work          # Check JSON
  DRY_RUN=1 gemini-profile.sh switch work  # Preview switch
USAGE
    exit 0
}

# ─── List Profiles ────────────────────────────────────────────────────────────

list_profiles() {
    if [ ! -d "$GEMINI_PROFILES_DIR" ]; then
        echo "No profiles found. Create one with: gemini-profile.sh create <name>"
        return
    fi

    local has_profiles=false
    echo "Available profiles:"
    echo ""

    shopt -s nullglob 2>/dev/null || true
    local dirs=("$GEMINI_PROFILES_DIR"/*/)
    shopt -u nullglob 2>/dev/null || true

    for profile_dir in "${dirs[@]}"; do
        [ -d "$profile_dir" ] || continue
        has_profiles=true
        local name
        name=$(basename "$profile_dir")

        local marker=""
        if [ -f "$GEMINI_ACTIVE_MARKER" ] && \
           [ "$(cat "$GEMINI_ACTIVE_MARKER")" = "$name" ]; then
            marker=" ✓"
        fi

        local settings_file="$profile_dir/settings.json"
        if [ -f "$settings_file" ]; then
            local settings_info
            settings_info=$(_parse_settings "$settings_file")
            echo "  - ${name}${marker}  ($settings_info)"

            # Show additional files
            _dir_summary "$profile_dir/commands" "Commands"

            if [ -f "$profile_dir/.env" ]; then
                local key_count
                key_count=$(grep -c '^[A-Za-z_]*_API_KEY=\|^[A-Za-z_]*_CREDENTIALS=' "$profile_dir/.env" 2>/dev/null || echo "0")
                printf '      API keys:  %s configured\n' "$key_count"
            fi

            if [ -f "$profile_dir/GEMINI.md" ]; then
                local lines
                lines=$(wc -l < "$profile_dir/GEMINI.md" | tr -d ' ')
                printf '      GEMINI.md: %s lines\n' "$lines"
            fi
        else
            echo "  - ${name}${marker}  (no settings.json)"
        fi
    done

    if [ "$has_profiles" = false ]; then
        echo "No profiles found. Create one with: gemini-profile.sh create <name>"
    fi
}

# ─── Current Profile ──────────────────────────────────────────────────────────

current_profile() {
    if [ -f "$GEMINI_ACTIVE_MARKER" ]; then
        local active
        active=$(cat "$GEMINI_ACTIVE_MARKER")
        echo "Current profile: $active"
        local settings_file="$GEMINI_PROFILES_DIR/$active/settings.json"
        if [ -f "$settings_file" ]; then
            echo "  Config: $(_parse_settings "$settings_file")"
        fi
    else
        echo "No profile selected. Using default config: $GEMINI_CONFIG_DIR"
        if [ -f "$GEMINI_CONFIG_DIR/settings.json" ]; then
            echo "  Config: $(_parse_settings "$GEMINI_CONFIG_DIR/settings.json")"
        fi
    fi
}

# ─── Switch Profile ───────────────────────────────────────────────────────────

switch_profile() {
    local profile="$1"
    local target_dir="$GEMINI_PROFILES_DIR/$profile"

    if [ ! -d "$target_dir" ]; then
        echo "❌ Error: Profile '$profile' not found."
        echo "Create it with: gemini-profile.sh create $profile"
        exit 1
    fi

    # Validate settings.json before switching
    local settings_file="$target_dir/settings.json"
    if [ -f "$settings_file" ]; then
        if ! _validate_json "$settings_file"; then
            echo "❌ Error: Profile settings.json has invalid JSON syntax."
            echo "File: $settings_file"
            echo "Fix the config or edit with: gemini-profile.sh edit $profile"
            exit 1
        fi
    fi

    # Backup current settings with timestamps
    if [ -f "$GEMINI_CONFIG_DIR/settings.json" ]; then
        _backup_file "$GEMINI_CONFIG_DIR/settings.json"
    fi
    if [ -f "$GEMINI_CONFIG_DIR/.env" ]; then
        _backup_file "$GEMINI_CONFIG_DIR/.env"
    fi

    # Restore profile files
    if [ -f "$settings_file" ]; then
        _dry_run cp "$settings_file" "$GEMINI_CONFIG_DIR/settings.json"
        echo "✓ Restored settings.json"
    fi

    if [ -f "$target_dir/.env" ]; then
        _dry_run cp "$target_dir/.env" "$GEMINI_CONFIG_DIR/.env"
        chmod 600 "$GEMINI_CONFIG_DIR/.env"
        echo "✓ Restored .env (API keys)"
    fi

    if [ -f "$target_dir/GEMINI.md" ]; then
        _dry_run cp "$target_dir/GEMINI.md" "$GEMINI_CONFIG_DIR/GEMINI.md"
        echo "✓ Restored GEMINI.md"
    fi

    if [ "${DRY_RUN:-0}" = "1" ]; then
        echo ""
        echo "🔍 [DRY RUN] Would switch to profile: $profile"
        echo "Remove DRY_RUN=1 to execute."
    else
        echo "$profile" > "$GEMINI_ACTIVE_MARKER"
        echo ""
        echo "✅ Switched to profile: $profile"
        echo ""
        if [ -f "$settings_file" ]; then
            echo "  Config: $(_parse_settings "$settings_file")"
        fi
        echo ""
        echo "Start Gemini CLI with: gemini"
    fi
}

# ─── Create Profile ───────────────────────────────────────────────────────────

create_profile() {
    local profile="${1:-}"

    if [ -z "$profile" ]; then
        echo "❌ Error: Profile name required."
        echo "Usage: gemini-profile.sh create <name>"
        exit 1
    fi

    if [[ ! "$profile" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo "❌ Error: Profile name can only contain letters, numbers, hyphens, and underscores."
        exit 1
    fi

    mkdir -p "$GEMINI_PROFILES_DIR/$profile"

    local copied=false
    if [ -f "$GEMINI_CONFIG_DIR/settings.json" ]; then
        cp "$GEMINI_CONFIG_DIR/settings.json" "$GEMINI_PROFILES_DIR/$profile/settings.json"
        copied=true
    fi
    if [ -f "$GEMINI_CONFIG_DIR/.env" ]; then
        cp "$GEMINI_CONFIG_DIR/.env" "$GEMINI_PROFILES_DIR/$profile/.env"
        chmod 600 "$GEMINI_PROFILES_DIR/$profile/.env"
        copied=true
    fi
    if [ -f "$GEMINI_CONFIG_DIR/GEMINI.md" ]; then
        cp "$GEMINI_CONFIG_DIR/GEMINI.md" "$GEMINI_PROFILES_DIR/$profile/GEMINI.md"
        copied=true
    fi

    if [ "$copied" = false ]; then
        cat > "$GEMINI_PROFILES_DIR/$profile/settings.json" << 'EOF'
{
  "model": "gemini-2.5-pro",
  "theme": "default",
  "autoAccept": false,
  "checkpointing": true
}
EOF
        cat > "$GEMINI_PROFILES_DIR/$profile/GEMINI.md" << EOF
# Gemini Profile: $profile
# Add your global instructions here.
EOF
        echo "⚠ No current config found. Created default profile."
    else
        echo "✓ Saved current config to profile"
    fi

    echo ""
    echo "✅ Created profile: $profile"
    echo "Config location: $GEMINI_PROFILES_DIR/$profile"
    echo ""
    local editor
    editor=$(_get_editor)
    echo "Edit settings: $editor $GEMINI_PROFILES_DIR/$profile/settings.json"
    echo "Activate: gemini-profile.sh switch $profile"
}

# ─── Edit Profile ─────────────────────────────────────────────────────────────

edit_profile() {
    local profile="${1:-}"
    local target_dir="$GEMINI_PROFILES_DIR/$profile"
    local settings_file="$target_dir/settings.json"

    if [ ! -d "$target_dir" ]; then
        echo "❌ Error: Profile '$profile' not found."
        echo "Create it with: gemini-profile.sh create $profile"
        exit 1
    fi

    if [ ! -f "$settings_file" ]; then
        echo "⚠ No settings.json yet. Creating default..."
        cat > "$settings_file" << 'EOF'
{
  "model": "gemini-2.5-pro",
  "theme": "default"
}
EOF
    fi

    local editor
    editor=$(_get_editor)

    echo "Opening $settings_file in $editor..."
    "$editor" "$settings_file"

    echo ""
    if _validate_json "$settings_file"; then
        echo "✅ settings.json saved and validated."
        echo ""
        echo "  Config: $(_parse_settings "$settings_file")"
    else
        echo "❌ settings.json has invalid JSON. Please fix before switching."
    fi
}

# ─── Validate Profile ─────────────────────────────────────────────────────────

validate_profile() {
    local profile="${1:-}"
    local target_dir="$GEMINI_PROFILES_DIR/$profile"
    local settings_file="$target_dir/settings.json"

    if [ ! -d "$target_dir" ]; then
        echo "❌ Error: Profile '$profile' not found."
        exit 1
    fi

    echo "Validating profile: $profile"
    echo "Directory: $target_dir"
    echo "---"

    local all_valid=true

    if [ -f "$settings_file" ]; then
        if _validate_json "$settings_file"; then
            echo "✅ settings.json — valid"
        else
            echo "❌ settings.json — invalid JSON"
            all_valid=false
        fi
    else
        echo "⚠ No settings.json found"
    fi

    local env_file="$target_dir/.env"
    if [ -f "$env_file" ]; then
        if _validate_env_file "$env_file" 2>/dev/null; then
            echo "✅ .env — valid"
        else
            echo "❌ .env — syntax errors"
            all_valid=false
        fi
    fi

    echo "---"
    if [ "$all_valid" = true ]; then
        echo "✅ All config files are valid."
        if [ -f "$settings_file" ]; then
            echo ""
            echo "  Config: $(_parse_settings "$settings_file")"
        fi
    else
        echo "❌ Some config files have errors."
        exit 1
    fi
}

# ─── Delete Profile ───────────────────────────────────────────────────────────

delete_profile() {
    local profile="${1:-}"
    local target_dir="$GEMINI_PROFILES_DIR/$profile"

    if [ -z "$profile" ]; then
        echo "❌ Error: Profile name required."
        exit 1
    fi

    if [ ! -d "$target_dir" ]; then
        echo "❌ Error: Profile '$profile' not found."
        exit 1
    fi

    read -r -p "Delete profile '$profile'? This cannot be undone. [y/N] " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        rm -rf "$target_dir"

        if [ -f "$GEMINI_ACTIVE_MARKER" ] && [ "$(cat "$GEMINI_ACTIVE_MARKER")" = "$profile" ]; then
            rm "$GEMINI_ACTIVE_MARKER"
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
            echo "Usage: gemini-profile.sh switch <name>"
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
