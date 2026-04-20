#!/usr/bin/env bash
# claude-profile.sh - Full config profile switcher for Claude Code CLI
#
# Manages complete Claude Code configurations via CLAUDE_CONFIG_DIR.
# Each profile is a fully self-contained ~/.claude/ directory with
# settings, credentials, commands, skills, agents, and session history.
#
# Usage:
#   claude-profile.sh list                        List all profiles
#   claude-profile.sh create <name>               Create profile from current config
#   claude-profile.sh switch <name>               Switch to a profile
#   claude-profile.sh delete <name>               Delete a profile
#   claude-profile.sh current                     Show active profile
#   claude-profile.sh edit <name>                 Edit settings.json in $EDITOR
#   claude-profile.sh validate <name>             Validate profile JSON
#
# Examples:
#   claude-profile.sh create work
#   claude-profile.sh switch personal
#   CLAUDE_CONFIG_DIR=~/.claude-profiles/work claude  # Direct override
#   DRY_RUN=1 claude-profile.sh switch work         # Preview switch

set -euo pipefail

# Claude Code respects CLAUDE_CONFIG_DIR — we use it for profile rotation
CLAUDE_PROFILES_DIR="${HOME}/.claude-profiles"
DEFAULT_CLAUDE_DIR="${HOME}/.claude"

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

# Parse model from settings.json
_parse_model() {
    local file="$1"
    if command -v python3 &>/dev/null; then
        python3 -c "
import json, os, sys
try:
    cfg = json.load(open(sys.argv[1]))
    # Claude Code settings.json doesn't have a 'model' key directly;
    # it stores env vars under 'env' key
    env = cfg.get('env', {})
    model = env.get('ANTHROPIC_MODEL', 'default (subscription)')
    print(model)
except:
    print('(parse error)')
" "$file" 2>/dev/null || echo "(parse error)"
    else
        echo "(no parser available)"
    fi
}

# Parse provider mode from settings.json
_parse_provider() {
    local file="$1"
    if command -v python3 &>/dev/null; then
        python3 -c "
import json, sys
try:
    cfg = json.load(open(sys.argv[1]))
    env = cfg.get('env', {})
    if env.get('CLAUDE_CODE_USE_BEDROCK') == '1':
        print(f\"bedrock ({env.get('AWS_REGION', 'unknown')})\")
    elif env.get('CLAUDE_CODE_USE_VERTEX') == '1':
        print(f\"vertex ({env.get('GOOGLE_CLOUD_PROJECT', 'unknown')})\")
    elif env.get('CLAUDE_CODE_USE_FOUNDRY') == '1':
        print('foundry')
    elif env.get('ANTHROPIC_API_KEY'):
        print('anthropic (direct API)')
    else:
        print('subscription (OAuth)')
except:
    print('unknown')
" "$file" 2>/dev/null || echo "unknown"
    else
        echo "unknown"
    fi
}

# List directory contents summary
_dir_summary() {
    local dir="$1"
    local name="$2"
    if [ -d "$dir" ]; then
        local count
        count=$(find "$dir" -maxdepth 1 -type f | wc -l | tr -d ' ')
        echo "      $name: $count file(s)"
    fi
}

# ─── Usage ────────────────────────────────────────────────────────────────────

usage() {
    cat << 'USAGE'
Claude Code CLI Profile Manager (CLAUDE_CONFIG_DIR Rotation)

Usage: claude-profile.sh [list|switch|create|delete|current|edit|validate] [name]

Commands:
  list                  List all available profiles
  switch <profile>      Switch to a profile (sets CLAUDE_CONFIG_DIR hint)
  create <profile>      Create a new profile from current config
  delete <profile>      Delete a profile
  current               Show current active profile
  edit <profile>        Edit profile settings.json in $EDITOR
  validate <profile>    Validate profile JSON syntax

Flags:
  DRY_RUN=1             Preview actions without executing

How it works:
  This script manages complete ~/.claude/ directories.
  To activate a profile, it writes CLAUDE_CONFIG_DIR to ~/.claude-active-profile.
  Source it to apply:  source ~/.claude-active-profile
  Or run directly:    CLAUDE_CONFIG_DIR=~/.claude-profiles/<name> claude

Profile structure:
  ~/.claude-profiles/
  └── <name>/
      ├── CLAUDE.md           # Global instructions
      ├── settings.json       # Tool permissions & env vars
      ├── settings.local.json # Personal overrides
      ├── commands/           # Custom slash commands
      ├── skills/             # Auto-invoked workflows
      ├── agents/             # Subagent personas
      └── .credentials.json   # OAuth tokens (if present)

Examples:
  claude-profile.sh create work
  claude-profile.sh switch personal
  claude-profile.sh edit work              # Open in $EDITOR
  claude-profile.sh validate work          # Check JSON
  DRY_RUN=1 claude-profile.sh switch work  # Preview switch
  source ~/.claude-active-profile           # Apply profile to shell
USAGE
    exit 0
}

# ─── List Profiles ────────────────────────────────────────────────────────────

list_profiles() {
    if [ ! -d "$CLAUDE_PROFILES_DIR" ]; then
        echo "No profiles found. Create one with: claude-profile.sh create <name>"
        return
    fi

    local has_profiles=false
    echo "Available profiles:"
    echo ""

    # Detect currently active profile
    local active_profile=""
    if [ -n "${CLAUDE_CONFIG_DIR:-}" ]; then
        for profile_dir in "$CLAUDE_PROFILES_DIR"/*/; do
            [ -d "$profile_dir" ] || continue
            local real_profile
            real_profile=$(cd "$profile_dir" && pwd)
            local real_config
            real_config=$(cd "$CLAUDE_CONFIG_DIR" 2>/dev/null && pwd || echo "")
            if [ "$real_profile" = "$real_config" ]; then
                active_profile=$(basename "$profile_dir")
                break
            fi
        done
    elif [ -f "$HOME/.claude-active-profile" ]; then
        active_profile=$(cat "$HOME/.claude-active-profile" 2>/dev/null || echo "")
    fi

    for profile_dir in "$CLAUDE_PROFILES_DIR"/*/; do
        [ -d "$profile_dir" ] || continue
        has_profiles=true
        local name
        name=$(basename "$profile_dir")

        local marker=""
        [ "$name" = "$active_profile" ] && marker=" ✓"

        local settings_file="$profile_dir/settings.json"
        if [ -f "$settings_file" ]; then
            local model provider
            model=$(_parse_model "$settings_file")
            provider=$(_parse_provider "$settings_file")

            echo "  - ${name}${marker}"
            echo "      Provider:  $provider"
            echo "      Model:     $model"

            # Show directory contents
            _dir_summary "$profile_dir/commands" "Commands"
            _dir_summary "$profile_dir/skills" "Skills"
            _dir_summary "$profile_dir/agents" "Agents"

            # Show if CLAUDE.md exists
            if [ -f "$profile_dir/CLAUDE.md" ]; then
                local lines
                lines=$(wc -l < "$profile_dir/CLAUDE.md" | tr -d ' ')
                echo "      CLAUDE.md: $lines lines"
            fi
        else
            echo "  - ${name}${marker}  (no settings.json)"
        fi
    done

    if [ "$has_profiles" = false ]; then
        echo "No profiles found. Create one with: claude-profile.sh create <name>"
    fi
}

# ─── Current Profile ──────────────────────────────────────────────────────────

current_profile() {
    if [ -n "${CLAUDE_CONFIG_DIR:-}" ]; then
        # Check if it matches a known profile
        for profile_dir in "$CLAUDE_PROFILES_DIR"/*/; do
            [ -d "$profile_dir" ] || continue
            local real_profile real_config
            real_profile=$(cd "$profile_dir" && pwd)
            real_config=$(cd "$CLAUDE_CONFIG_DIR" 2>/dev/null && pwd || echo "")
            if [ "$real_profile" = "$real_config" ]; then
                local name
                name=$(basename "$profile_dir")
                echo "Current profile (from CLAUDE_CONFIG_DIR): $name"
                echo "  Config dir: $CLAUDE_CONFIG_DIR"
                if [ -f "$profile_dir/settings.json" ]; then
                    echo "  Provider:  $(_parse_provider "$profile_dir/settings.json")"
                    echo "  Model:     $(_parse_model "$profile_dir/settings.json")"
                fi
                return
            fi
        done
        echo "Current CLAUDE_CONFIG_DIR: $CLAUDE_CONFIG_DIR"
        echo "  (not a managed profile)"
    elif [ -f "$HOME/.claude-active-profile" ]; then
        local active
        active=$(cat "$HOME/.claude-active-profile")
        echo "Current profile: $active"
        local settings_file="$CLAUDE_PROFILES_DIR/$active/settings.json"
        if [ -f "$settings_file" ]; then
            echo "  Provider:  $(_parse_provider "$settings_file")"
            echo "  Model:     $(_parse_model "$settings_file")"
        fi
    else
        echo "No profile selected. Using default config: $DEFAULT_CLAUDE_DIR"
        if [ -f "$DEFAULT_CLAUDE_DIR/settings.json" ]; then
            echo "  Provider:  $(_parse_provider "$DEFAULT_CLAUDE_DIR/settings.json")"
            echo "  Model:     $(_parse_model "$DEFAULT_CLAUDE_DIR/settings.json")"
        fi
    fi
}

# ─── Switch Profile ───────────────────────────────────────────────────────────

switch_profile() {
    local profile="$1"
    local target_dir="$CLAUDE_PROFILES_DIR/$profile"

    if [ ! -d "$target_dir" ]; then
        echo "❌ Error: Profile '$profile' not found."
        echo "Create it with: claude-profile.sh create $profile"
        exit 1
    fi

    # Validate settings.json before switching
    local settings_file="$target_dir/settings.json"
    if [ -f "$settings_file" ]; then
        if ! _validate_json "$settings_file"; then
            echo "❌ Error: Profile settings.json has invalid JSON syntax."
            echo "File: $settings_file"
            echo "Fix the config or edit with: claude-profile.sh edit $profile"
            exit 1
        fi
    fi

    if [ "${DRY_RUN:-0}" = "1" ]; then
        echo "🔍 [DRY RUN] Would activate profile: $profile"
        echo ""
        echo "Would set:"
        echo "  CLAUDE_CONFIG_DIR=$target_dir"
        echo ""
        echo "Would write to: $HOME/.claude-active-profile"
        echo "Remove DRY_RUN=1 to execute."
        return
    fi

    # Write activation script
    cat > "$HOME/.claude-active-profile" << EOF
# Claude Code Profile: $profile
# Source this file to activate: source ~/.claude-active-profile
export CLAUDE_CONFIG_DIR="$target_dir"
echo "✅ Claude Code profile activated: $profile"
echo "   CLAUDE_CONFIG_DIR=$target_dir"
EOF

    # Also export in current shell
    export CLAUDE_CONFIG_DIR="$target_dir"

    echo "✅ Switched to profile: $profile"
    echo ""
    echo "  CLAUDE_CONFIG_DIR=$target_dir"
    if [ -f "$settings_file" ]; then
        echo "  Provider:  $(_parse_provider "$settings_file")"
        echo "  Model:     $(_parse_model "$settings_file")"
    fi
    echo ""
    echo "This profile is now active in the current shell."
    echo "Start a new shell? Run:  source ~/.claude-active-profile"
    echo "Or run directly: CLAUDE_CONFIG_DIR=$target_dir claude"
}

# ─── Create Profile ───────────────────────────────────────────────────────────

create_profile() {
    local profile="${1:-}"

    if [ -z "$profile" ]; then
        echo "❌ Error: Profile name required."
        echo "Usage: claude-profile.sh create <name>"
        exit 1
    fi

    if [[ ! "$profile" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo "❌ Error: Profile name can only contain letters, numbers, hyphens, and underscores."
        exit 1
    fi

    local target_dir="$CLAUDE_PROFILES_DIR/$profile"
    mkdir -p "$target_dir"

    # Determine source config dir
    local source_dir=""
    if [ -n "${CLAUDE_CONFIG_DIR:-}" ] && [ -d "$CLAUDE_CONFIG_DIR" ]; then
        source_dir="$CLAUDE_CONFIG_DIR"
    elif [ -d "$DEFAULT_CLAUDE_DIR" ]; then
        source_dir="$DEFAULT_CLAUDE_DIR"
    fi

    if [ -n "$source_dir" ] && [ -d "$source_dir" ]; then
        # Copy entire .claude/ directory structure
        # Exclude large session data, keep config files
        if command -v rsync &>/dev/null; then
            rsync -a \
                --exclude='projects/' \
                --exclude='*.log' \
                --exclude='node_modules/' \
                "$source_dir/" "$target_dir/"
        else
            cp -R "$source_dir"/* "$target_dir/" 2>/dev/null || true
            rm -rf "$target_dir/projects" 2>/dev/null || true
        fi
        echo "✓ Copied config from: $source_dir"
    else
        # Create minimal default profile
        cat > "$target_dir/settings.json" << 'EOF'
{
  "permissions": {
    "allow": [],
    "deny": []
  }
}
EOF
        cat > "$target_dir/CLAUDE.md" << EOF
# Claude Code Profile: $profile
# Add your global instructions here.
EOF
        echo "⚠ No existing config found. Created default profile."
    fi

    echo ""
    echo "✅ Created profile: $profile"
    echo "Config location: $target_dir"
    echo ""
    echo "Directory contents:"
    ls -1 "$target_dir" | sed 's/^/  /'
    echo ""
    local editor
    editor=$(_get_editor)
    echo "Edit settings: $editor $target_dir/settings.json"
    echo "Activate: claude-profile.sh switch $profile"
}

# ─── Edit Profile ─────────────────────────────────────────────────────────────

edit_profile() {
    local profile="${1:-}"
    local target_dir="$CLAUDE_PROFILES_DIR/$profile"
    local settings_file="$target_dir/settings.json"

    if [ ! -d "$target_dir" ]; then
        echo "❌ Error: Profile '$profile' not found."
        echo "Create it with: claude-profile.sh create $profile"
        exit 1
    fi

    if [ ! -f "$settings_file" ]; then
        echo "⚠ No settings.json yet. Creating default..."
        cat > "$settings_file" << 'EOF'
{
  "permissions": {
    "allow": [],
    "deny": []
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
        echo "  Provider: $(_parse_provider "$settings_file")"
        echo "  Model:    $(_parse_model "$settings_file")"
    else
        echo "❌ settings.json has invalid JSON. Please fix before switching."
    fi
}

# ─── Validate Profile ─────────────────────────────────────────────────────────

validate_profile() {
    local profile="${1:-}"
    local target_dir="$CLAUDE_PROFILES_DIR/$profile"
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

    # Validate settings.local.json if exists
    local local_settings="$target_dir/settings.local.json"
    if [ -f "$local_settings" ]; then
        if _validate_json "$local_settings"; then
            echo "✅ settings.local.json — valid"
        else
            echo "❌ settings.local.json — invalid JSON"
            all_valid=false
        fi
    fi

    # Validate .mcp.json if exists
    local mcp_file="$target_dir/.mcp.json"
    if [ -f "$mcp_file" ]; then
        if _validate_json "$mcp_file"; then
            echo "✅ .mcp.json — valid"
        else
            echo "❌ .mcp.json — invalid JSON"
            all_valid=false
        fi
    fi

    echo "---"
    if [ "$all_valid" = true ]; then
        echo "✅ All config files are valid."
        echo ""
        if [ -f "$settings_file" ]; then
            echo "  Provider: $(_parse_provider "$settings_file")"
            echo "  Model:    $(_parse_model "$settings_file")"
        fi
    else
        echo "❌ Some config files have errors."
        exit 1
    fi
}

# ─── Delete Profile ───────────────────────────────────────────────────────────

delete_profile() {
    local profile="${1:-}"
    local target_dir="$CLAUDE_PROFILES_DIR/$profile"

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

        # Clear active profile if it was the deleted one
        if [ -f "$HOME/.claude-active-profile" ]; then
            local active
            active=$(cat "$HOME/.claude-active-profile" 2>/dev/null | grep -o 'CLAUDE_CONFIG_DIR="[^"]*"' | sed 's/.*=//;s/"//g' | xargs basename 2>/dev/null || echo "")
            if [ "$active" = "$profile" ]; then
                rm "$HOME/.claude-active-profile"
                unset CLAUDE_CONFIG_DIR 2>/dev/null || true
                echo "✓ Cleared active profile"
            fi
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
            echo "Usage: claude-profile.sh switch <name>"
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
