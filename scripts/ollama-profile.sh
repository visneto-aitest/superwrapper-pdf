#!/usr/bin/env bash
# ollama-profile.sh - Modelfile profile manager for Ollama
#
# Manages custom model profiles (Modelfiles) that define system prompts,
# parameters, and templates for different use cases.
#
# Usage:
#   ollama-profile.sh list                        List all profiles
#   ollama-profile.sh create <name>               Create profile from current Modelfile
#   ollama-profile.sh switch <name>               Create model from profile
#   ollama-profile.sh delete <name>               Delete a profile
#   ollama-profile.sh current                     Show active profile
#   ollama-profile.sh edit <name>                 Edit Modelfile in $EDITOR
#   ollama-profile.sh validate <name>             Validate Modelfile syntax
#   ollama-profile.sh deploy <name>               Build and deploy model to Ollama
#
# Examples:
#   ollama-profile.sh create coder
#   ollama-profile.sh switch writer
#   ollama-profile.sh deploy coder                # ollama create coder-profile -f Modelfile

set -euo pipefail

OLLAMA_PROFILES_DIR="${HOME}/.config/ollama/profiles"
OLLAMA_ACTIVE_MARKER="${HOME}/.config/ollama/.active-profile"
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
    _backup_file() { local f="$1"; if [ -f "$f" ]; then local d b t; d=$(dirname "$f"); b=$(basename "$f"); t=$(date +%Y%m%d_%H%M%S); local bk="${d}/${b}.backup_${t}"; cp "$f" "$bk"; chmod 600 "$bk"; printf '  Backed up to: %s\n' "$(basename "$bk")"; fi; }
fi

# ─── Helpers ──────────────────────────────────────────────────────────────────

_parse_modelfile() {
    local file="$1"
    if [ ! -f "$file" ]; then
        echo "not found"
        return
    fi

    python3 -c '
import sys, re

try:
    with open(sys.argv[1]) as f:
        content = f.read()

    base_model = ""
    system_prompt = ""
    params = []
    template = ""

    for line in content.strip().split("\n"):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        upper = line.upper()
        if upper.startswith("FROM "):
            base_model = line[5:].strip().strip("\"'")
        elif upper.startswith("SYSTEM "):
            system_prompt = line[7:].strip().strip("\"'")[:60]
        elif upper.startswith("PARAMETER "):
            parts = line[10:].strip().split(None, 1)
            if len(parts) == 2:
                params.append(f"{parts[0]}={parts[1]}")
        elif upper.startswith("TEMPLATE "):
            template = "(set)"

    info = []
    if base_model:
        info.append(f"base: {base_model}")
    if params:
        info.append(f"params: {", ".join(params)}")
    if system_prompt:
        info.append(f"system: {system_prompt}...")
    if template:
        info.append("template: set")

    print(" | ".join(info) if info else "(empty modelfile)")
except Exception as e:
    print(f"parse error: {e}")
' "$file" 2>/dev/null || echo "(parse error)"
}

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
Ollama Modelfile Profile Manager

Usage: ollama-profile.sh [list|switch|create|delete|current|edit|validate|deploy] [name]

Commands:
  list                  List all available profiles
  switch <profile>      Activate a profile (sets active marker)
  create <profile>      Create a new Modelfile profile
  delete <profile>      Delete a profile
  current               Show current active profile
  edit <profile>        Edit profile Modelfile in $EDITOR
  validate <profile>    Validate Modelfile syntax
  deploy <profile>      Build and deploy model to Ollama

Flags:
  DRY_RUN=1             Preview actions without executing

How it works:
  Each profile is a Modelfile that defines:
  - Base model (FROM)
  - System prompt (SYSTEM)
  - Parameters (PARAMETER temperature 0.7, etc.)
  - Prompt template (TEMPLATE)
  - Example conversations (MESSAGE)

  Deploy creates a custom model in Ollama from the Modelfile.

Examples:
  ollama-profile.sh create coder
  ollama-profile.sh switch writer
  ollama-profile.sh edit coder              # Open in $EDITOR
  ollama-profile.sh deploy coder            # ollama create coder-profile -f Modelfile
  DRY_RUN=1 ollama-profile.sh deploy coder  # Preview deploy
USAGE
    exit 0
}

# ─── List ─────────────────────────────────────────────────────────────────────

list_profiles() {
    if [ ! -d "$OLLAMA_PROFILES_DIR" ]; then
        echo "No profiles found. Create one with: ollama-profile.sh create <name>"
        return
    fi

    local has_profiles=false
    echo "Available profiles:"
    echo ""

    local active_profile=""
    if [ -f "$OLLAMA_ACTIVE_MARKER" ]; then
        active_profile=$(cat "$OLLAMA_ACTIVE_MARKER")
    fi

    (
        shopt -s nullglob 2>/dev/null || true
        local dirs=("$OLLAMA_PROFILES_DIR"/*/)
        shopt -u nullglob 2>/dev/null || true

        for profile_dir in "${dirs[@]}"; do
        [ -d "$profile_dir" ] || continue
        has_profiles=true
        local name
        name=$(basename "$profile_dir")

        local marker=""
        [ "$name" = "$active_profile" ] && marker=" *"

        local modelfile="$profile_dir/Modelfile"
        if [ -f "$modelfile" ]; then
            local info
            info=$(_parse_modelfile "$modelfile")
            echo "  - ${name}${marker}  ($info)"
        else
            echo "  - ${name}${marker}  (no Modelfile)"
        fi
        done
    )

    if [ "$has_profiles" = false ]; then
        echo "No profiles found. Create one with: ollama-profile.sh create <name>"
    fi

    echo ""
    echo "Profiles directory: $OLLAMA_PROFILES_DIR"
}

# ─── Current ──────────────────────────────────────────────────────────────────

current_profile() {
    if [ -f "$OLLAMA_ACTIVE_MARKER" ]; then
        local active
        active=$(cat "$OLLAMA_ACTIVE_MARKER")
        echo "Current profile: $active"
        local modelfile="$OLLAMA_PROFILES_DIR/$active/Modelfile"
        if [ -f "$modelfile" ]; then
            echo "  Modelfile: $(_parse_modelfile "$modelfile")"
        fi
    else
        echo "No active profile. Using default Ollama settings."
    fi
}

# ─── Switch ───────────────────────────────────────────────────────────────────

switch_profile() {
    local profile="$1"
    local target_dir="$OLLAMA_PROFILES_DIR/$profile"

    if [ ! -d "$target_dir" ]; then
        echo "Error: Profile '$profile' not found."
        echo "Create it with: ollama-profile.sh create $profile"
        exit 1
    fi

    if [ ! -f "$target_dir/Modelfile" ]; then
        echo "Error: No Modelfile in profile '$profile'."
        echo "Edit it first: ollama-profile.sh edit $profile"
        exit 1
    fi

    if [ "${DRY_RUN:-0}" = "1" ]; then
        echo "🔍 [DRY RUN] Would activate profile: $profile"
        echo ""
        echo "Would write: $OLLAMA_ACTIVE_MARKER"
        echo "Remove DRY_RUN=1 to execute."
        return
    fi

    echo "$profile" > "$OLLAMA_ACTIVE_MARKER"

    echo "Switched to profile: $profile"
    echo "  Modelfile: $target_dir/Modelfile"
    echo ""
    echo "To deploy: ollama-profile.sh deploy $profile"
    echo "Or manually: ollama create $profile -f $target_dir/Modelfile"
}

# ─── Create ───────────────────────────────────────────────────────────────────

create_profile() {
    local profile="${1:-}"

    if [ -z "$profile" ]; then
        echo "Error: Profile name required."
        echo "Usage: ollama-profile.sh create <name>"
        exit 1
    fi

    if [[ ! "$profile" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo "Error: Name can only contain letters, numbers, hyphens, and underscores."
        exit 1
    fi

    mkdir -p "$OLLAMA_PROFILES_DIR/$profile"

    local modelfile="$OLLAMA_PROFILES_DIR/$profile/Modelfile"

    if [ -f "$modelfile" ]; then
        echo "Error: Profile '$profile' already exists."
        echo "Edit it with: ollama-profile.sh edit $profile"
        exit 1
    fi

    cat > "$modelfile" << 'EOF'
# Ollama Modelfile Profile
# Define your custom model configuration here.

# Base model (required)
FROM llama3.2

# System prompt
# SYSTEM You are a helpful coding assistant.

# Parameters
# PARAMETER temperature 0.7
# PARAMETER num_ctx 4096
# PARAMETER num_predict 2048
# PARAMETER top_p 0.9
# PARAMETER top_k 40
# PARAMETER repeat_penalty 1.1

# Prompt template (Go template syntax)
# TEMPLATE """{{ if .System }}<|system|>
# {{ .System }}<|end|>
# {{ end }}<|user|>
# {{ .Prompt }}<|end|>
# <|assistant|>"""

# Example conversation
# MESSAGE user "What is 2+2?"
# MESSAGE assistant "2+2 equals 4."
EOF

    echo "Created profile: $profile"
    echo "Modelfile: $modelfile"
    echo ""
    echo "Next steps:"
    echo "  1. Edit the Modelfile: ollama-profile.sh edit $profile"
    echo "  2. Set FROM to your base model and configure parameters"
    echo "  3. Deploy: ollama-profile.sh deploy $profile"
}

# ─── Edit ─────────────────────────────────────────────────────────────────────

edit_profile() {
    local profile="${1:-}"
    local target_dir="$OLLAMA_PROFILES_DIR/$profile"
    local modelfile="$target_dir/Modelfile"

    if [ ! -d "$target_dir" ]; then
        echo "Error: Profile '$profile' not found."
        echo "Create it with: ollama-profile.sh create $profile"
        exit 1
    fi

    if [ ! -f "$modelfile" ]; then
        echo "No Modelfile yet. Creating default..."
        cat > "$modelfile" << 'EOF'
FROM llama3.2
EOF
    fi

    local editor
    editor=$(_get_editor)

    echo "Opening $modelfile in $editor..."
    "$editor" "$modelfile"

    echo ""
    if _validate_modelfile "$modelfile"; then
        echo "Modelfile saved and validated."
        echo ""
        echo "  Profile: $(_parse_modelfile "$modelfile")"
    else
        echo "Modelfile saved but has warnings."
    fi
}

# ─── Validate ─────────────────────────────────────────────────────────────────

_validate_modelfile() {
    local file="$1"
    local errors=0

    if [ ! -f "$file" ]; then
        echo "  File not found: $file"
        return 1
    fi

    local has_from=false
    local line_num=0

    while IFS= read -r line || [ -n "$line" ]; do
        line_num=$((line_num + 1))

        # Skip empty lines and comments
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue

        local upper
        upper=$(echo "$line" | tr '[:lower:]' '[:upper:]' | sed 's/^[[:space:]]*//')

        case "$upper" in
            FROM\ *) has_from=true ;;
            PARAMETER\ *) ;;
            SYSTEM\ *) ;;
            TEMPLATE\ *) ;;
            MESSAGE\ *) ;;
            ADAPTER\ *) ;;
            LICENSE\ *) ;;
            REQUIRES\ *) ;;
            *)
                echo "  ⚠ Line $line_num: Unknown instruction: ${line:0:50}"
                errors=$((errors + 1))
                ;;
        esac
    done < "$file"

    if [ "$has_from" = false ]; then
        echo "  Error: Modelfile must have a FROM instruction"
        errors=$((errors + 1))
    fi

    if [ "$errors" -gt 0 ]; then
        return 1
    fi
    return 0
}

validate_profile() {
    local profile="${1:-}"
    local target_dir="$OLLAMA_PROFILES_DIR/$profile"
    local modelfile="$target_dir/Modelfile"

    if [ ! -d "$target_dir" ]; then
        echo "Error: Profile '$profile' not found."
        exit 1
    fi

    echo "Validating profile: $profile"
    echo "Directory: $target_dir"
    echo "---"

    local all_valid=true

    if [ -f "$modelfile" ]; then
        if _validate_modelfile "$modelfile"; then
            echo "✅ Modelfile - valid"
        else
            echo "❌ Modelfile - has errors (see above)"
            all_valid=false
        fi
    else
        echo "⚠ No Modelfile found"
    fi

    echo "---"
    if [ "$all_valid" = true ]; then
        echo "All config files are valid."
        if [ -f "$modelfile" ]; then
            echo ""
            echo "  Profile: $(_parse_modelfile "$modelfile")"
        fi
    else
        echo "Some config files have errors."
        exit 1
    fi
}

# ─── Deploy ───────────────────────────────────────────────────────────────────

deploy_profile() {
    local profile="${1:-}"
    local target_dir="$OLLAMA_PROFILES_DIR/$profile"
    local modelfile="$target_dir/Modelfile"

    if [ ! -d "$target_dir" ]; then
        echo "Error: Profile '$profile' not found."
        echo "Create it with: ollama-profile.sh create $profile"
        exit 1
    fi

    if [ ! -f "$modelfile" ]; then
        echo "Error: No Modelfile in profile '$profile'."
        echo "Edit it first: ollama-profile.sh edit $profile"
        exit 1
    fi

    if ! _validate_modelfile "$modelfile"; then
        echo "Error: Modelfile has errors. Fix before deploying."
        exit 1
    fi

    local model_name="${profile}-profile"

    if [ "${DRY_RUN:-0}" = "1" ]; then
        echo "🔍 [DRY RUN] Would execute:"
        echo "  ollama create $model_name -f $modelfile"
        echo "Remove DRY_RUN=1 to execute."
        return
    fi

    echo "Deploying profile '$profile' as model '$model_name'..."
    echo ""

    if ollama create "$model_name" -f "$modelfile"; then
        echo ""
        echo "Successfully deployed: $model_name"
        echo ""
        echo "Test it: ollama run $model_name"
        echo "Show info: ollama show $model_name"
    else
        echo "Failed to deploy. Check the Modelfile and Ollama server status."
        exit 1
    fi
}

# ─── Delete ───────────────────────────────────────────────────────────────────

delete_profile() {
    local profile="${1:-}"
    local target_dir="$OLLAMA_PROFILES_DIR/$profile"

    if [ -z "$profile" ]; then
        echo "Error: Profile name required."
        exit 1
    fi

    if [ ! -d "$target_dir" ]; then
        echo "Error: Profile '$profile' not found."
        exit 1
    fi

    read -r -p "Delete profile '$profile'? This cannot be undone. [y/N] " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        rm -rf "$target_dir"

        if [ -f "$OLLAMA_ACTIVE_MARKER" ] && [ "$(cat "$OLLAMA_ACTIVE_MARKER")" = "$profile" ]; then
            rm "$OLLAMA_ACTIVE_MARKER"
            echo "Cleared active profile"
        fi

        echo "Deleted profile: $profile"
    else
        echo "Cancelled."
    fi
}

# ─── Main ─────────────────────────────────────────────────────────────────────

case "${1:-}" in
    list) list_profiles ;;
    switch)
        if [ -z "${2:-}" ]; then
            echo "Error: Profile name required."
            echo "Usage: ollama-profile.sh switch <name>"
            exit 1
        fi
        switch_profile "$2"
        ;;
    create) create_profile "${2:-}" ;;
    delete) delete_profile "${2:-}" ;;
    current) current_profile ;;
    edit) edit_profile "${2:-}" ;;
    validate) validate_profile "${2:-}" ;;
    deploy) deploy_profile "${2:-}" ;;
    *) usage ;;
esac
