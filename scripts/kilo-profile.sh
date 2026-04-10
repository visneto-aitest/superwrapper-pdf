#!/usr/bin/env bash
# kilo-profile.sh - Full config profile switcher for Kilo CLI
#
# Manages complete Kilo CLI configurations as kilo.jsonc files.
# Each profile is a self-contained directory with kilo.jsonc and
# optional OAuth credentials. API keys use {env:VAR_NAME} syntax.
#
# Usage:
#   kilo-profile.sh list                        List all profiles
#   kilo-profile.sh create <name>               Create profile from current config
#   kilo-profile.sh switch <name>               Switch to a profile
#   kilo-profile.sh delete <name>               Delete a profile
#   kilo-profile.sh current                     Show active profile
#   kilo-profile.sh edit <name>                 Edit kilo.jsonc in $EDITOR
#   kilo-profile.sh validate <name>             Validate profile JSONC
#
# Examples:
#   kilo-profile.sh create work
#   kilo-profile.sh switch personal
#   DRY_RUN=1 kilo-profile.sh switch work   # Preview switch

set -euo pipefail

KILO_CONFIG_DIR="${HOME}/.config/kilo"
KILO_PROFILES_DIR="${KILO_CONFIG_DIR}/profiles"
KILO_ACTIVE_MARKER="${KILO_CONFIG_DIR}/.active_profile"
AUTH_DIR="${HOME}/.local/share/kilo"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source shared library
if [ -f "$SCRIPT_DIR/lib/common.sh" ]; then
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/lib/common.sh"
else
    _get_editor() { printf '%s' "${EDITOR:-${VISUAL:-nano}}"; }
    _hash_string() { printf '%s' "$1" | shasum -a 256 2>/dev/null | cut -d' ' -f1 || printf '%s' "$1" | sha256sum 2>/dev/null | cut -d' ' -f1 || echo "unknown"; }
    _validate_json() { local f="$1"; if command -v python3 &>/dev/null; then python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$f" 2>/dev/null || return 1; elif command -v jq &>/dev/null; then jq empty "$f" 2>/dev/null || return 1; fi; return 0; }
    _dry_run() { if [ "${DRY_RUN:-0}" = "1" ]; then printf '🔍 [DRY RUN] Would execute: %s\n' "$*"; return 0; else "$@"; fi; }
    _backup_file() { local f="$1"; if [ -f "$f" ]; then local d b t; d=$(dirname "$f"); b=$(basename "$f"); t=$(date +%Y%m%d_%H%M%S); local bk="${d}/${b}.backup_${t}"; cp "$f" "$bk"; chmod 600 "$bk"; printf '  ✓ Backed up to: %s\n' "$(basename "$bk")"; fi; }
fi

# ─── Helpers ──────────────────────────────────────────────────────────────────

# Parse model and provider summary from kilo.jsonc
_parse_config() {
    local file="$1"
    if command -v python3 &>/dev/null; then
        python3 -c '
import json, sys
try:
    cfg = json.load(open(sys.argv[1]))
    model = cfg.get("model", "not set")
    providers = list(cfg.get("provider", {}).keys())
    disabled = set(cfg.get("disabled_providers", []))
    enabled = [p for p in providers if p not in disabled]
    prov_str = ",".join(enabled) if enabled else "(none)"
    print(f"model: {model} | providers: {prov_str}")
except Exception as e:
    print(f"parse error: {e}")
' "$file" 2>/dev/null || echo "(parse error)"
    else
        echo "(no parser available)"
    fi
}

# List directory contents summary
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
Kilo CLI Profile Manager (kilo.jsonc Rotation)

Usage: kilo-profile.sh [list|switch|create|delete|current|edit|validate] [name]

Commands:
  list                  List all available profiles
  switch <profile>      Switch to a profile
  create <profile>      Create a new profile from current config
  delete <profile>      Delete a profile
  current               Show current active profile
  edit <profile>        Edit profile kilo.jsonc in $EDITOR
  validate <profile>    Validate profile JSONC syntax

Flags:
  DRY_RUN=1             Preview actions without executing

How it works:
  Kilo CLI uses ~/.config/kilo/kilo.jsonc for configuration.
  This script manages complete kilo.jsonc files from isolated
  profile directories. API keys use {env:VAR_NAME} syntax
  and are provided by environment variables (see kilo-env.sh).

Profile structure:
  ~/.config/kilo/profiles/
  └── <name>/
      ├── kilo.jsonc          # Provider, model, permissions, MCP config
      └── auth.json           # OAuth credentials (optional, for GitHub Copilot)

Examples:
  kilo-profile.sh create work
  kilo-profile.sh switch personal
  kilo-profile.sh edit work              # Open in $EDITOR
  kilo-profile.sh validate work          # Check JSONC
  DRY_RUN=1 kilo-profile.sh switch work  # Preview switch
USAGE
    exit 0
}

# ─── List Profiles ────────────────────────────────────────────────────────────

list_profiles() {
    if [ ! -d "$KILO_PROFILES_DIR" ]; then
        echo "No profiles found. Create one with: kilo-profile.sh create <name>"
        return
    fi

    local has_profiles=false
    echo "Available profiles:"
    echo ""

    shopt -s nullglob 2>/dev/null || true
    local dirs=("$KILO_PROFILES_DIR"/*/)
    shopt -u nullglob 2>/dev/null || true

    for profile_dir in "${dirs[@]}"; do
        [ -d "$profile_dir" ] || continue
        has_profiles=true
        local name
        name=$(basename "$profile_dir")

        local marker=""
        if [ -f "$KILO_ACTIVE_MARKER" ] && \
           [ "$(cat "$KILO_ACTIVE_MARKER")" = "$name" ]; then
            marker=" ✓"
        fi

        local config_file="$profile_dir/kilo.jsonc"
        if [ -f "$config_file" ]; then
            local config_info
            config_info=$(_parse_config "$config_file")
            echo "  - ${name}${marker}  ($config_info)"

            _dir_summary "$profile_dir/mcp" "MCP configs"

            if [ -f "$profile_dir/auth.json" ]; then
                echo "      OAuth:     configured"
            fi
        else
            echo "  - ${name}${marker}  (no kilo.jsonc)"
        fi
    done

    if [ "$has_profiles" = false ]; then
        echo "No profiles found. Create one with: kilo-profile.sh create <name>"
    fi
}

# ─── Current Profile ──────────────────────────────────────────────────────────

current_profile() {
    if [ -f "$KILO_ACTIVE_MARKER" ]; then
        local active
        active=$(cat "$KILO_ACTIVE_MARKER")
        echo "Current profile: $active"
        local config_file="$KILO_PROFILES_DIR/$active/kilo.jsonc"
        if [ -f "$config_file" ]; then
            echo "  Config: $(_parse_config "$config_file")"
        fi
    else
        echo "No profile selected. Using default config: $KILO_CONFIG_DIR/kilo.jsonc"
        if [ -f "$KILO_CONFIG_DIR/kilo.jsonc" ]; then
            echo "  Config: $(_parse_config "$KILO_CONFIG_DIR/kilo.jsonc")"
        fi
    fi
}

# ─── Switch Profile ───────────────────────────────────────────────────────────

switch_profile() {
    local profile="$1"
    local target_dir="$KILO_PROFILES_DIR/$profile"

    if [ ! -d "$target_dir" ]; then
        echo "❌ Error: Profile '$profile' not found."
        echo "Create it with: kilo-profile.sh create $profile"
        exit 1
    fi

    # Validate kilo.jsonc before switching
    local config_file="$target_dir/kilo.jsonc"
    if [ -f "$config_file" ]; then
        if ! _validate_json "$config_file"; then
            echo "❌ Error: Profile kilo.jsonc has invalid JSON syntax."
            echo "File: $config_file"
            echo "Fix the config or edit with: kilo-profile.sh edit $profile"
            exit 1
        fi
    fi

    if [ "${DRY_RUN:-0}" = "1" ]; then
        echo "🔍 [DRY RUN] Would switch to profile: $profile"
        echo ""
        echo "Would backup current:"
        [ -f "$KILO_CONFIG_DIR/kilo.jsonc" ] && echo "  $KILO_CONFIG_DIR/kilo.jsonc"
        [ -f "$AUTH_DIR/auth.json" ] && echo "  $AUTH_DIR/auth.json"
        echo ""
        echo "Would restore from:"
        [ -f "$config_file" ] && echo "  $config_file → $KILO_CONFIG_DIR/kilo.jsonc"
        [ -f "$target_dir/auth.json" ] && echo "  $target_dir/auth.json → $AUTH_DIR/auth.json"
        echo ""
        echo "Would write: $KILO_ACTIVE_MARKER"
        echo "Remove DRY_RUN=1 to execute."
        return
    fi

    # Backup current config with timestamps
    if [ -f "$KILO_CONFIG_DIR/kilo.jsonc" ]; then
        _backup_file "$KILO_CONFIG_DIR/kilo.jsonc"
    fi
    if [ -f "$AUTH_DIR/auth.json" ]; then
        _backup_file "$AUTH_DIR/auth.json"
    fi

    # Restore profile config
    if [ -f "$config_file" ]; then
        cp "$config_file" "$KILO_CONFIG_DIR/kilo.jsonc"
        echo "✓ Restored kilo.jsonc"
    else
        echo "⚠ Warning: No kilo.jsonc in profile '$profile'"
    fi

    # Restore OAuth credentials if present
    if [ -f "$target_dir/auth.json" ]; then
        mkdir -p "$AUTH_DIR"
        cp "$target_dir/auth.json" "$AUTH_DIR/auth.json"
        chmod 600 "$AUTH_DIR/auth.json"
        echo "✓ Restored OAuth credentials"
    fi

    # Save active profile marker
    echo "$profile" > "$KILO_ACTIVE_MARKER"

    echo ""
    echo "✅ Switched to profile: $profile"
    echo ""
    if [ -f "$config_file" ]; then
        echo "  Config: $(_parse_config "$config_file")"
    fi
    echo ""
    echo "Start Kilo with: kilo"
}

# ─── Create Profile ───────────────────────────────────────────────────────────

create_profile() {
    local profile="${1:-}"

    if [ -z "$profile" ]; then
        echo "❌ Error: Profile name required."
        echo "Usage: kilo-profile.sh create <name>"
        exit 1
    fi

    if [[ ! "$profile" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo "❌ Error: Profile name can only contain letters, numbers, hyphens, and underscores."
        exit 1
    fi

    mkdir -p "$KILO_PROFILES_DIR/$profile"

    # Try to generate kilo.jsonc from auth.json + current config
    local copied=false
    if [ -f "$KILO_CONFIG_DIR/kilo.jsonc" ]; then
        cp "$KILO_CONFIG_DIR/kilo.jsonc" "$KILO_PROFILES_DIR/$profile/kilo.jsonc"
        copied=true
    fi
    if [ -f "$AUTH_DIR/auth.json" ]; then
        cp "$AUTH_DIR/auth.json" "$KILO_PROFILES_DIR/$profile/auth.json"
        chmod 600 "$KILO_PROFILES_DIR/$profile/auth.json"
        copied=true
    fi

    if [ "$copied" = false ]; then
        # No existing config — try to auto-generate from auth.json
        if [ -f "$AUTH_DIR/auth.json" ] && command -v python3 &>/dev/null; then
            python3 -c '
import json, sys, os

auth_file = sys.argv[1]
out_file = sys.argv[2]
try:
    auth = json.load(open(auth_file))
    providers = {}
    for name, entry in auth.items():
        ptype = entry.get("type", "")
        if ptype == "api":
            env_var = name.upper().replace("-", "_") + "_API_KEY"
            providers[name] = {"options": {"apiKey": "{env:" + env_var + "}"}}
        elif ptype == "oauth":
            providers[name] = {"options": {}}
    # Pick a sensible default model
    model = "openrouter/anthropic/claude-sonnet-4-20250514"
    if "anthropic" in providers:
        model = "anthropic/claude-sonnet-4-20250514"
    elif "openai" in providers:
        model = "openai/gpt-4o"
    config = {
        "$schema": "https://app.kilo.ai/config.json",
        "model": model,
        "provider": providers
    }
    with open(out_file, "w") as f:
        json.dump(config, f, indent=2)
        f.write("\n")
except Exception as e:
    print(f"Error generating config: {e}", file=sys.stderr)
    sys.exit(1)
' "$AUTH_DIR/auth.json" "$KILO_PROFILES_DIR/$profile/kilo.jsonc" && {
                echo "✓ Auto-generated kilo.jsonc from auth.json"
            } || {
                # Fallback: create minimal default
                cat > "$KILO_PROFILES_DIR/$profile/kilo.jsonc" << 'KILJSONC'
{
  "$schema": "https://app.kilo.ai/config.json",
  "model": "anthropic/claude-sonnet-4-20250514",
  "provider": {
    "anthropic": {
      "options": {
        "apiKey": "{env:ANTHROPIC_API_KEY}"
      }
    }
  }
}
KILJSONC
                echo "⚠ Could not auto-generate. Created default profile."
            }
        else
            cat > "$KILO_PROFILES_DIR/$profile/kilo.jsonc" << 'KILJSONC'
{
  "$schema": "https://app.kilo.ai/config.json",
  "model": "anthropic/claude-sonnet-4-20250514",
  "provider": {
    "anthropic": {
      "options": {
        "apiKey": "{env:ANTHROPIC_API_KEY}"
      }
    }
  }
}
KILJSONC
            echo "⚠ No current config or auth.json found. Created default profile."
        fi
    else
        echo "✓ Saved current config to profile"
    fi

    echo ""
    echo "✅ Created profile: $profile"
    echo "Config location: $KILO_PROFILES_DIR/$profile"
    echo ""
    local editor
    editor=$(_get_editor)
    echo "Edit config: $editor $KILO_PROFILES_DIR/$profile/kilo.jsonc"
    echo "Activate:    kilo-profile.sh switch $profile"
    echo ""
    echo "Note: API keys use {env:VAR_NAME} syntax in kilo.jsonc."
    echo "      Set env vars via: kilo-env.sh <account>"
    echo "      OAuth providers need no env vars — credentials are in auth.json."
}

# ─── Edit Profile ─────────────────────────────────────────────────────────────

edit_profile() {
    local profile="${1:-}"
    local target_dir="$KILO_PROFILES_DIR/$profile"
    local config_file="$target_dir/kilo.jsonc"

    if [ ! -d "$target_dir" ]; then
        echo "❌ Error: Profile '$profile' not found."
        echo "Create it with: kilo-profile.sh create $profile"
        exit 1
    fi

    if [ ! -f "$config_file" ]; then
        echo "⚠ No kilo.jsonc yet. Creating default..."
        cat > "$config_file" << 'EOF'
{
  "$schema": "https://app.kilo.ai/config.json",
  "model": "anthropic/claude-sonnet-4-20250514"
}
EOF
    fi

    local editor
    editor=$(_get_editor)

    echo "Opening $config_file in $editor..."
    "$editor" "$config_file"

    echo ""
    if _validate_json "$config_file"; then
        echo "✅ kilo.jsonc saved and validated."
        echo ""
        echo "  Config: $(_parse_config "$config_file")"
    else
        echo "❌ kilo.jsonc has invalid JSON. Please fix before switching."
    fi
}

# ─── Validate Profile ─────────────────────────────────────────────────────────

validate_profile() {
    local profile="${1:-}"
    local target_dir="$KILO_PROFILES_DIR/$profile"
    local config_file="$target_dir/kilo.jsonc"

    if [ ! -d "$target_dir" ]; then
        echo "❌ Error: Profile '$profile' not found."
        exit 1
    fi

    echo "Validating profile: $profile"
    echo "Directory: $target_dir"
    echo "---"

    local all_valid=true

    if [ -f "$config_file" ]; then
        if _validate_json "$config_file"; then
            echo "✅ kilo.jsonc — valid"
        else
            echo "❌ kilo.jsonc — invalid JSON"
            all_valid=false
        fi
    else
        echo "⚠ No kilo.jsonc found"
    fi

    if [ -f "$target_dir/auth.json" ]; then
        if _validate_json "$target_dir/auth.json"; then
            echo "✅ auth.json — valid"
        else
            echo "❌ auth.json — invalid JSON"
            all_valid=false
        fi
    fi

    echo "---"
    if [ "$all_valid" = true ]; then
        echo "✅ All config files are valid."
        if [ -f "$config_file" ]; then
            echo ""
            echo "  Config: $(_parse_config "$config_file")"
        fi
    else
        echo "❌ Some config files have errors."
        exit 1
    fi
}

# ─── Delete Profile ───────────────────────────────────────────────────────────

delete_profile() {
    local profile="${1:-}"
    local target_dir="$KILO_PROFILES_DIR/$profile"

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

        if [ -f "$KILO_ACTIVE_MARKER" ] && [ "$(cat "$KILO_ACTIVE_MARKER")" = "$profile" ]; then
            rm "$KILO_ACTIVE_MARKER"
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
