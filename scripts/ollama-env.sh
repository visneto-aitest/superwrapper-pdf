#!/usr/bin/env bash
# ollama-env.sh - Environment-based server config switcher for Ollama
#
# Ollama is configured via environment variables, not config files.
# This script manages multiple Ollama server configurations using .env files.
#
# Usage:
#   ollama-env.sh list                        List all configurations
#   ollama-env.sh create <name>               Create new config
#   ollama-env.sh show <name>                 Show config details
#   ollama-env.sh edit <name>                 Edit config in $EDITOR
#   ollama-env.sh validate <name>             Validate config syntax
#   ollama-env.sh <name>                      Export vars to current shell
#   ollama-env.sh <name> ollama [args...]     Run ollama with config
#
# Examples:
#   ollama-env.sh create gpu-heavy
#   ollama-env.sh create low-memory
#   ollama-env.sh gpu-heavy                   # Export vars
#   ollama-env.sh gpu-heavy ollama list       # Run ollama with config

set -euo pipefail

OLLAMA_ACCOUNTS_DIR="${OLLAMA_ACCOUNTS_DIR:-${HOME}/.config/ollama/accounts}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source shared library
if [ -f "$SCRIPT_DIR/lib/common.sh" ]; then
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/lib/common.sh"
else
    _get_editor() { printf '%s' "${EDITOR:-${VISUAL:-nano}}"; }
    _hash_string() { printf '%s' "$1" | shasum -a 256 2>/dev/null | cut -d' ' -f1 || printf '%s' "$1" | sha256sum 2>/dev/null | cut -d' ' -f1 || echo "unknown"; }
    _mask_value() { local v="$1" l=${#1}; if [ "$l" -gt 12 ]; then printf '%s' "${v:0:4}****${v: -4} ($l chars)"; elif [ "$l" -gt 0 ]; then printf '%s' "****(masked)"; else printf '%s' "(not set)"; fi; }
    _validate_env_file() { local f="$1" ln=0 er=0; while IFS= read -r line || [ -n "$line" ]; do ln=$((ln+1)); [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue; if [[ ! "$line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then printf '  ⚠ Line %d: Invalid format\n' "$ln"; er=$((er+1)); fi; done < "$f"; [ "$er" -gt 0 ] && return 1; return 0; }
    _validate_json() { local f="$1"; if command -v python3 &>/dev/null; then python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$f" 2>/dev/null || return 1; elif command -v jq &>/dev/null; then jq empty "$f" 2>/dev/null || return 1; fi; return 0; }
    _dry_run() { if [ "${DRY_RUN:-0}" = "1" ]; then printf '🔍 [DRY RUN] Would execute: %s\n' "$*"; return 0; else "$@"; fi; }
    _grep_env_key() { local r=""; r=$(grep -E "^${1}=" "$2" 2>/dev/null | head -1 | cut -d'=' -f2-) || r=""; printf '%s' "$r"; }
fi

# ─── Ollama environment variables ─────────────────────────────────────────────

OLLAMA_VARS=(
    "OLLAMA_HOST"
    "OLLAMA_MODELS"
    "OLLAMA_KEEP_ALIVE"
    "OLLAMA_LOAD_TIMEOUT"
    "OLLAMA_NUM_PARALLEL"
    "OLLAMA_MAX_LOADED_MODELS"
    "OLLAMA_MAX_QUEUE"
    "OLLAMA_CONTEXT_LENGTH"
    "OLLAMA_SCHED_SPREAD"
    "OLLAMA_DEBUG"
    "OLLAMA_ORIGINS"
    "OLLAMA_FLASH_ATTN"
    "OLLAMA_KV_CACHE_TYPE"
    "OLLAMA_LLM_LIBRARY"
    "OLLAMA_GPU_OVERHEAD"
    "CUDA_VISIBLE_DEVICES"
    "HIP_VISIBLE_DEVICES"
    "HSA_OVERRIDE_GFX_VERSION"
)

OLLAMA_SECRET_VARS=(
    "OLLAMA_API_KEY"
)

# ─── Usage ────────────────────────────────────────────────────────────────────

usage() {
    cat << 'USAGE'
Ollama Server Configuration Manager (Environment-based)

Usage: ollama-env.sh <command> [arguments]

Commands:
  list                  List available configurations
  create <name>         Create new config
  show <name>           Show configuration details
  edit <name>           Edit config in $EDITOR
  validate <name>       Validate config syntax
  <name>                Export vars to current shell
  <name> <command>      Run command with config

Flags:
  DRY_RUN=1             Preview actions without executing

Examples:
  ollama-env.sh create gpu-heavy
  ollama-env.sh create low-memory
  ollama-env.sh gpu-heavy                 # Export vars
  ollama-env.sh gpu-heavy ollama list     # Run with config
  ollama-env.sh edit gpu-heavy            # Edit in $EDITOR

Environment Variables:
  OLLAMA_HOST               Server bind address (default: 127.0.0.1:11434)
  OLLAMA_MODELS             Model storage path
  OLLAMA_KEEP_ALIVE         Model memory retention duration (e.g., 5m, -1)
  OLLAMA_NUM_PARALLEL       Max parallel inference requests
  OLLAMA_MAX_LOADED_MODELS  Max models loaded per GPU
  OLLAMA_CONTEXT_LENGTH     Default context window size
  OLLAMA_SCHED_SPREAD       Spread across all GPUs (true/false)
  OLLAMA_DEBUG              Verbose logging (true/false)
  CUDA_VISIBLE_DEVICES      Restrict visible NVIDIA GPUs
  OLLAMA_API_KEY            API key for ollama.com cloud services
USAGE
    exit 0
}

# ─── List ─────────────────────────────────────────────────────────────────────

list_accounts() {
    if [ ! -d "$OLLAMA_ACCOUNTS_DIR" ]; then
        echo "No configurations found."
        echo "Create one with: ollama-env.sh create <name>"
        return
    fi

    local has_configs=false
    echo "Available configurations:"
    echo ""

    shopt -s nullglob 2>/dev/null || true
    local files=("$OLLAMA_ACCOUNTS_DIR"/*.env)
    shopt -u nullglob 2>/dev/null || true

    for file in "${files[@]}"; do
        [ -f "$file" ] || continue
        has_configs=true
        local name
        name=$(basename "$file" .env)

        # Determine profile characteristics
        local host model_path keep_alive parallel ctx
        host=$(_grep_env_key "OLLAMA_HOST" "$file")
        model_path=$(_grep_env_key "OLLAMA_MODELS" "$file")
        keep_alive=$(_grep_env_key "OLLAMA_KEEP_ALIVE" "$file")
        parallel=$(_grep_env_key "OLLAMA_NUM_PARALLEL" "$file")
        ctx=$(_grep_env_key "OLLAMA_CONTEXT_LENGTH" "$file")

        local info=""
        [ -n "$host" ] && info="$host" || info="127.0.0.1:11434"
        [ -n "$parallel" ] && info="$info | parallel=$parallel"
        [ -n "$ctx" ] && info="$info | ctx=$ctx"
        [ -n "$keep_alive" ] && info="$info | keep_alive=$keep_alive"

        # Check if this config matches current server
        local current_host="${OLLAMA_HOST:-127.0.0.1:11434}"
        local marker=""
        if [ "$host" = "$current_host" ] || { [ -z "$host" ] && [ "$current_host" = "127.0.0.1:11434" ]; }; then
            marker=" ✓"
        fi

        echo "  • ${name}${marker}  ($info)"
    done

    if [ "$has_configs" = false ]; then
        echo "No configurations found."
        echo "Create one with: ollama-env.sh create <name>"
    fi

    echo ""
    echo "Configs directory: $OLLAMA_ACCOUNTS_DIR"
}

# ─── Create ───────────────────────────────────────────────────────────────────

create_account() {
    local name="${1:-}"

    if [ -z "$name" ]; then
        echo "Error: Configuration name required."
        echo "Usage: ollama-env.sh create <name>"
        exit 1
    fi

    if [[ ! "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo "Error: Name can only contain letters, numbers, hyphens, and underscores."
        exit 1
    fi

    mkdir -p "$OLLAMA_ACCOUNTS_DIR"

    local file="$OLLAMA_ACCOUNTS_DIR/$name.env"

    if [ -f "$file" ]; then
        echo "Error: Configuration '$name' already exists."
        echo "Edit it with: ollama-env.sh edit $name"
        exit 1
    fi

    cat > "$file" << 'EOF'
# Ollama Server Configuration
# Environment variables that control Ollama server behavior.

# ─── Server Binding ─────────────────────────────────────────────
# OLLAMA_HOST=127.0.0.1:11434
# OLLAMA_ORIGINS=*

# ─── Model Storage ──────────────────────────────────────────────
# OLLAMA_MODELS=/Volumes/External/ollama-models

# ─── Memory & Performance ───────────────────────────────────────
# OLLAMA_KEEP_ALIVE=5m           # Keep models in memory (default: 5m, -1 = forever)
# OLLAMA_LOAD_TIMEOUT=5m         # Max time to wait for model loading
# OLLAMA_NUM_PARALLEL=1          # Max concurrent inference requests
# OLLAMA_MAX_LOADED_MODELS=0     # Max models per GPU (0 = auto)
# OLLAMA_MAX_QUEUE=512           # Max queued requests
# OLLAMA_CONTEXT_LENGTH=0        # Default context window (0 = auto)

# ─── GPU Configuration ─────────────────────────────────────────
# CUDA_VISIBLE_DEVICES=0         # Use only GPU 0
# OLLAMA_SCHED_SPREAD=false      # Spread across all GPUs
# OLLAMA_FLASH_ATTN=true         # Enable flash attention
# OLLAMA_KV_CACHE_TYPE=f16       # KV cache precision
# OLLAMA_GPU_OVERHEAD=0          # VRAM overhead reservation

# ─── Debug ──────────────────────────────────────────────────────
# OLLAMA_DEBUG=false             # Enable verbose debug logging
EOF

    chmod 600 "$file"

    echo "Created configuration: $name"
    echo "Config file: $file"
    echo ""
    echo "Next steps:"
    echo "  1. Edit the file: ollama-env.sh edit $name"
    echo "  2. Set desired environment variables"
    echo "  3. Activate: ollama-env.sh $name"
    echo "  4. Start server: OLLAMA_DEBUG=true ollama serve"
}

# ─── Show ─────────────────────────────────────────────────────────────────────

show_account() {
    local name="${1:-}"
    local file="$OLLAMA_ACCOUNTS_DIR/$name.env"

    if [ ! -f "$file" ]; then
        echo "Error: Configuration '$name' not found."
        echo "Available configurations:"
        list_accounts
        exit 1
    fi

    echo "Configuration: $name"
    echo "File: $file"
    echo "Last modified: $(stat -f '%Sm' "$file" 2>/dev/null || stat -c '%y' "$file" 2>/dev/null || echo "unknown")"
    echo "---"

    echo "Configured variables:"
    local has_vars=false
    for var in "${OLLAMA_VARS[@]}"; do
        local file_val
        file_val=$(_grep_env_key "$var" "$file")
        if [ -n "$file_val" ]; then
            has_vars=true
            echo "  $var: $file_val"
        fi
    done

    [ "$has_vars" = false ] && echo "  (no variables configured — using defaults)"
    echo "---"

    if ! _validate_env_file "$file" 2>/dev/null; then
        echo "Config has syntax warnings (see above)"
    fi
}

# ─── Edit ─────────────────────────────────────────────────────────────────────

edit_account() {
    local name="${1:-}"
    local file="$OLLAMA_ACCOUNTS_DIR/$name.env"

    if [ ! -f "$file" ]; then
        echo "Error: Configuration '$name' not found."
        echo "Create it with: ollama-env.sh create $name"
        exit 1
    fi

    local editor
    editor=$(_get_editor)

    echo "Opening $file in $editor..."
    "$editor" "$file"

    echo ""
    if _validate_env_file "$file"; then
        echo "Config saved and validated."
    else
        echo "Config saved but has syntax warnings. Review above."
    fi
}

# ─── Validate ─────────────────────────────────────────────────────────────────

validate_account() {
    local name="${1:-}"
    local file="$OLLAMA_ACCOUNTS_DIR/$name.env"

    if [ ! -f "$file" ]; then
        echo "Error: Configuration '$name' not found."
        exit 1
    fi

    echo "Validating: $name"
    echo "File: $file"
    echo "---"

    if _validate_env_file "$file"; then
        echo "---"
        echo "Config syntax is valid."
    else
        echo "---"
        echo "Config has syntax errors (see above)."
        exit 1
    fi
}

# ─── Load ─────────────────────────────────────────────────────────────────────

load_account() {
    local name="$1"
    local file="$OLLAMA_ACCOUNTS_DIR/$name.env"

    if [ ! -f "$file" ]; then
        echo "Error: Configuration '$name' not found at $file"
        echo ""
        echo "Available configurations:"
        list_accounts
        exit 1
    fi

    set -a
    # shellcheck disable=SC1090
    source "$file"
    set +a

    echo "Loaded configuration: $name"
    echo "  Host: ${OLLAMA_HOST:-127.0.0.1:11434}"
    [ -n "${OLLAMA_MODELS:-}" ] && echo "  Models path: $OLLAMA_MODELS"
    [ -n "${OLLAMA_KEEP_ALIVE:-}" ] && echo "  Keep alive: $OLLAMA_KEEP_ALIVE"
    [ -n "${OLLAMA_NUM_PARALLEL:-}" ] && echo "  Parallel: $OLLAMA_NUM_PARALLEL"
    [ -n "${CUDA_VISIBLE_DEVICES:-}" ] && echo "  CUDA devices: $CUDA_VISIBLE_DEVICES"
    [ -n "${OLLAMA_DEBUG:-}" ] && echo "  Debug: $OLLAMA_DEBUG"

    echo ""
    echo "Environment variables exported to current shell."
    echo "Start server: ollama serve"
}

# ─── Run With Config ──────────────────────────────────────────────────────────

run_with_account() {
    local name="$1"
    shift

    local file="$OLLAMA_ACCOUNTS_DIR/$name.env"

    if [ ! -f "$file" ]; then
        echo "Error: Configuration '$name' not found at $file"
        exit 1
    fi

    (
        set -a
        # shellcheck disable=SC1090
        source "$file"
        set +a

        if [ $# -eq 0 ]; then
            echo "Error: No command specified."
            echo "Usage: ollama-env.sh $name <command> [args...]"
            exit 1
        fi

        exec "$@"
    )
}

# ─── Main ─────────────────────────────────────────────────────────────────────

case "${1:-}" in
    list) list_accounts ;;
    create) create_account "${2:-}" ;;
    show) show_account "${2:-}" ;;
    edit) edit_account "${2:-}" ;;
    validate) validate_account "${2:-}" ;;
    ""|--help|-h|help) usage ;;
    *)
        if [ -f "$OLLAMA_ACCOUNTS_DIR/$1.env" ]; then
            if [ "${2:-}" = "" ]; then
                load_account "$1"
            else
                shift
                run_with_account "$@"
            fi
        else
            echo "Error: Unknown command or configuration: $1"
            echo ""
            usage
        fi
        ;;
esac
