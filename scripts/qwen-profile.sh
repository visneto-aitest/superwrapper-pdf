#!/usr/bin/env bash
# qwen-profile.sh - Full config profile switcher for Qwen Code CLI
#
# Manages complete Qwen Code configurations including settings.json,
# .env files, and OAuth credentials. Each profile is an isolated directory.
#
# Usage:
#   qwen-profile.sh list                        List all profiles
#   qwen-profile.sh create <name>               Create profile from current config
#   qwen-profile.sh switch <name>               Switch to a profile
#   qwen-profile.sh delete <name>               Delete a profile
#   qwen-profile.sh current                     Show active profile
#   qwen-profile.sh edit <name>                 Edit settings.json in $EDITOR
#   qwen-profile.sh validate <name>             Validate profile JSON
#
# Examples:
#   qwen-profile.sh create work
#   qwen-profile.sh switch personal
#   DRY_RUN=1 qwen-profile.sh switch work   # Preview switch

set -euo pipefail

QWEN_CONFIG_DIR="${HOME}/.qwen"
QWEN_PROFILES_DIR="${QWEN_CONFIG_DIR}/profiles"
QWEN_ACTIVE_MARKER="${QWEN_CONFIG_DIR}/.active-profile"

# ─── Helpers ──────────────────────────────────────────────────────────────────

_get_editor() {
    echo "${EDITOR:-${VISUAL:-nano}}"
}

_validate_json() {
    local file="$1"
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

_dry_run() {
    if [ "${DRY_RUN:-0}" = "1" ]; then
        echo "🔍 [DRY RUN] Would execute: $*"
        return 0
    else
        "$@"
    fi
}

# Parse modelProviders from settings.json
_parse_model_providers() {
    local file="$1"
    if command -v python3 &>/dev/null; then
        python3 -c "
import json, sys
try:
    cfg = json.load(open(sys.argv[1]))
    mp = cfg.get('modelProviders', {})
    providers = []
    for auth_type, models in mp.items():
        if isinstance(models, list):
            for m in models:
                mid = m.get('id', '?')
                providers.append(f'{auth_type}/{mid}')
    if providers:
        print(', '.join(providers))
    else:
        print('(no providers configured)')
except:
    print('(parse error)')
" "$file" 2>/dev/null || echo "(parse error)"
    else
        echo "(no parser available)"
    fi
}

# Parse codingPlan region
_parse_region() {
    local file="$1"
    if command -v python3 &>/dev/null; then
        python3 -c "
import json, sys
try:
    cfg = json.load(open(sys.argv[1]))
    region = cfg.get('codingPlan', {}).get('region', 'default')
    print(region)
except:
    print('unknown')
" "$file" 2>/dev/null || echo "unknown"
    else
        echo "unknown"
    fi
}

# ─── Usage ────────────────────────────────────────────────────────────────────

usage() {
    cat << 'USAGE'
Qwen Code CLI Profile Manager (Full Config Rotation)

Usage: qwen-profile.sh [list|switch|create|delete|current|edit|validate] [name]

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
  Qwen Code uses ~/.qwen/settings.json for modelProviders definition
  and ~/.qwen/.env for API keys. This script rotates both files
  from isolated profile directories.

Profile structure:
  ~/.qwen/profiles/
  └── <name>/
      ├── settings.json       # modelProviders + codingPlan config
      ├── .env                # API keys (recommended)
      └── oauth_creds.json    # OAuth credentials (if used)

Examples:
  qwen-profile.sh create work
  qwen-profile.sh switch personal
  qwen-profile.sh edit work              # Open in $EDITOR
  qwen-profile.sh validate work          # Check JSON
  DRY_RUN=1 qwen-profile.sh switch work  # Preview switch
USAGE
    exit 0
}

# ─── List Profiles ────────────────────────────────────────────────────────────

list_profiles() {
    if [ ! -d "$QWEN_PROFILES_DIR" ]; then
        echo "No profiles found. Create one with: qwen-profile.sh create <name>"
        return
    fi

    local has_profiles=false
    echo "Available profiles:"
    echo ""

    for profile_dir in "$QWEN_PROFILES_DIR"/*/; do
        [ -d "$profile_dir" ] || continue
        has_profiles=true
        local name
        name=$(basename "$profile_dir")

        local marker=""
        if [ -f "$QWEN_ACTIVE_MARKER" ] && \
           [ "$(cat "$QWEN_ACTIVE_MARKER")" = "$name" ]; then
            marker=" ✓"
        fi

        local settings_file="$profile_dir/settings.json"
        if [ -f "$settings_file" ]; then
            local providers region
            providers=$(_parse_model_providers "$settings_file")
            region=$(_parse_region "$settings_file")

            echo "  - ${name}${marker}"
            echo "      Providers: $providers"
            echo "      Region:    $region"

            # Show if .env exists
            if [ -f "$profile_dir/.env" ]; then
                local key_count
                key_count=$(grep -c '^[A-Za-z_]*_API_KEY=' "$profile_dir/.env" 2>/dev/null || echo "0")
                echo "      API keys:  $key_count configured"
            fi

            # Show if oauth_creds.json exists
            if [ -f "$profile_dir/oauth_creds.json" ]; then
                echo "      OAuth:     configured"
            fi
        else
            echo "  - ${name}${marker}  (no settings.json)"
        fi
    done

    if [ "$has_profiles" = false ]; then
        echo "No profiles found. Create one with: qwen-profile.sh create <name>"
    fi
}

# ─── Current Profile ──────────────────────────────────────────────────────────

current_profile() {
    if [ -f "$QWEN_ACTIVE_MARKER" ]; then
        local active
        active=$(cat "$QWEN_ACTIVE_MARKER")
        echo "Current profile: $active"
        local settings_file="$QWEN_PROFILES_DIR/$active/settings.json"
        if [ -f "$settings_file" ]; then
            echo ""
            echo "  Providers: $(_parse_model_providers "$settings_file")"
            echo "  Region:    $(_parse_region "$settings_file")"
        fi
    else
        echo "No profile selected. Using default config: $QWEN_CONFIG_DIR"
        if [ -f "$QWEN_CONFIG_DIR/settings.json" ]; then
            echo ""
            echo "  Providers: $(_parse_model_providers "$QWEN_CONFIG_DIR/settings.json")"
        fi
    fi
}

# ─── Switch Profile ───────────────────────────────────────────────────────────

switch_profile() {
    local profile="$1"
    local target_dir="$QWEN_PROFILES_DIR/$profile"

    if [ ! -d "$target_dir" ]; then
        echo "❌ Error: Profile '$profile' not found."
        echo "Create it with: qwen-profile.sh create $profile"
        exit 1
    fi

    # Validate settings.json
    local settings_file="$target_dir/settings.json"
    if [ -f "$settings_file" ]; then
        if ! _validate_json "$settings_file"; then
            echo "❌ Error: Profile settings.json has invalid JSON syntax."
            echo "File: $settings_file"
            echo "Fix the config or edit with: qwen-profile.sh edit $profile"
            exit 1
        fi
    fi

    # Backup current settings
    if [ -f "$QWEN_CONFIG_DIR/settings.json" ]; then
        cp "$QWEN_CONFIG_DIR/settings.json" "$QWEN_CONFIG_DIR/settings.json.bak"
    fi
    if [ -f "$QWEN_CONFIG_DIR/.env" ]; then
        cp "$QWEN_CONFIG_DIR/.env" "$QWEN_CONFIG_DIR/.env.bak"
    fi
    if [ -f "$QWEN_CONFIG_DIR/oauth_creds.json" ]; then
        cp "$QWEN_CONFIG_DIR/oauth_creds.json" "$QWEN_CONFIG_DIR/oauth_creds.json.bak"
    fi

    # Restore profile files
    if [ -f "$settings_file" ]; then
        _dry_run cp "$settings_file" "$QWEN_CONFIG_DIR/settings.json"
        echo "✓ Restored settings.json"
    fi

    if [ -f "$target_dir/.env" ]; then
        _dry_run cp "$target_dir/.env" "$QWEN_CONFIG_DIR/.env"
        chmod 600 "$QWEN_CONFIG_DIR/.env"
        echo "✓ Restored .env (API keys)"
    fi

    if [ -f "$target_dir/oauth_creds.json" ]; then
        _dry_run cp "$target_dir/oauth_creds.json" "$QWEN_CONFIG_DIR/oauth_creds.json"
        chmod 600 "$QWEN_CONFIG_DIR/oauth_creds.json"
        echo "✓ Restored OAuth credentials"
    fi

    # Save active profile marker
    if [ "${DRY_RUN:-0}" = "1" ]; then
        echo ""
        echo "🔍 [DRY RUN] Would switch to profile: $profile"
        echo "Remove DRY_RUN=1 to execute."
    else
        echo "$profile" > "$QWEN_ACTIVE_MARKER"
        echo ""
        echo "✅ Switched to profile: $profile"
        echo ""
        echo "  Providers: $(_parse_model_providers "$settings_file")"
        echo ""
        echo "Start Qwen Code with: qwen"
    fi
}

# ─── Create Profile ───────────────────────────────────────────────────────────

create_profile() {
    local profile="${1:-}"

    if [ -z "$profile" ]; then
        echo "❌ Error: Profile name required."
        echo "Usage: qwen-profile.sh create <name>"
        exit 1
    fi

    if [[ ! "$profile" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo "❌ Error: Profile name can only contain letters, numbers, hyphens, and underscores."
        exit 1
    fi

    mkdir -p "$QWEN_PROFILES_DIR/$profile"

    # Copy current settings
    local copied=false
    if [ -f "$QWEN_CONFIG_DIR/settings.json" ]; then
        cp "$QWEN_CONFIG_DIR/settings.json" "$QWEN_PROFILES_DIR/$profile/settings.json"
        copied=true
    fi
    if [ -f "$QWEN_CONFIG_DIR/.env" ]; then
        cp "$QWEN_CONFIG_DIR/.env" "$QWEN_PROFILES_DIR/$profile/.env"
        chmod 600 "$QWEN_PROFILES_DIR/$profile/.env"
        copied=true
    fi
    if [ -f "$QWEN_CONFIG_DIR/oauth_creds.json" ]; then
        cp "$QWEN_CONFIG_DIR/oauth_creds.json" "$QWEN_PROFILES_DIR/$profile/oauth_creds.json"
        chmod 600 "$QWEN_PROFILES_DIR/$profile/oauth_creds.json"
        copied=true
    fi

    if [ "$copied" = false ]; then
        cat > "$QWEN_PROFILES_DIR/$profile/settings.json" << 'EOF'
{
  "modelProviders": {
    "openai": [
      {
        "id": "gpt-4-turbo",
        "envKey": "OPENAI_API_KEY"
      }
    ],
    "anthropic": [
      {
        "id": "claude-sonnet-4-20250514",
        "envKey": "ANTHROPIC_API_KEY"
      }
    ]
  },
  "codingPlan": {
    "region": "cn-hangzhou"
  }
}
EOF
        echo "⚠ No current config found. Created default profile."
    else
        echo "✓ Saved current config to profile"
    fi

    echo ""
    echo "✅ Created profile: $profile"
    echo "Config location: $QWEN_PROFILES_DIR/$profile"
    echo ""
    local editor
    editor=$(_get_editor)
    echo "Edit settings: $editor $QWEN_PROFILES_DIR/$profile/settings.json"
    echo "Activate: qwen-profile.sh switch $profile"
}

# ─── Edit Profile ─────────────────────────────────────────────────────────────

edit_profile() {
    local profile="${1:-}"
    local target_dir="$QWEN_PROFILES_DIR/$profile"
    local settings_file="$target_dir/settings.json"

    if [ ! -d "$target_dir" ]; then
        echo "❌ Error: Profile '$profile' not found."
        echo "Create it with: qwen-profile.sh create $profile"
        exit 1
    fi

    if [ ! -f "$settings_file" ]; then
        echo "⚠ No settings.json yet. Creating default..."
        cat > "$settings_file" << 'EOF'
{
  "modelProviders": {
    "openai": [
      {
        "id": "gpt-4-turbo",
        "envKey": "OPENAI_API_KEY"
      }
    ]
  }
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
        echo "  Providers: $(_parse_model_providers "$settings_file")"
        echo "  Region:    $(_parse_region "$settings_file")"
    else
        echo "❌ settings.json has invalid JSON. Please fix before switching."
    fi
}

# ─── Validate Profile ─────────────────────────────────────────────────────────

validate_profile() {
    local profile="${1:-}"
    local target_dir="$QWEN_PROFILES_DIR/$profile"
    local settings_file="$target_dir/settings.json"

    if [ ! -d "$target_dir" ]; then
        echo "❌ Error: Profile '$profile' not found."
        exit 1
    fi

    echo "Validating profile: $profile"
    echo "Directory: $target_dir"
    echo "---"

    local all_valid=true

    # Validate settings.json
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

    # Validate oauth_creds.json if exists
    local oauth_file="$target_dir/oauth_creds.json"
    if [ -f "$oauth_file" ]; then
        if _validate_json "$oauth_file"; then
            echo "✅ oauth_creds.json — valid"
        else
            echo "❌ oauth_creds.json — invalid JSON"
            all_valid=false
        fi
    fi

    # Validate .env if exists
    local env_file="$target_dir/.env"
    if [ -f "$env_file" ]; then
        local env_errors=0
        local line_num=0
        while IFS= read -r line || [ -n "$line" ]; do
            line_num=$((line_num + 1))
            [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
            if [[ ! "$line" =~ ^[A-Za-z_]+= ]]; then
                echo "  ⚠ .env line $line_num: Invalid format"
                env_errors=$((env_errors + 1))
            fi
        done < "$env_file"
        if [ $env_errors -eq 0 ]; then
            echo "✅ .env — valid"
        else
            echo "❌ .env — $env_errors error(s)"
            all_valid=false
        fi
    fi

    echo "---"
    if [ "$all_valid" = true ]; then
        echo "✅ All config files are valid."
        echo ""
        if [ -f "$settings_file" ]; then
            echo "  Providers: $(_parse_model_providers "$settings_file")"
            echo "  Region:    $(_parse_region "$settings_file")"
        fi
    else
        echo "❌ Some config files have errors."
        exit 1
    fi
}

# ─── Delete Profile ───────────────────────────────────────────────────────────

delete_profile() {
    local profile="${1:-}"
    local target_dir="$QWEN_PROFILES_DIR/$profile"

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

        if [ -f "$QWEN_ACTIVE_MARKER" ] && [ "$(cat "$QWEN_ACTIVE_MARKER")" = "$profile" ]; then
            rm "$QWEN_ACTIVE_MARKER"
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
            echo "Usage: qwen-profile.sh switch <name>"
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
