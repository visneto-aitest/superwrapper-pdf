#!/usr/bin/env bash
# ollama-status.sh - Check server status, models, GPU usage for Ollama
#
# Ollama has no native status command. This script:
#   1. Checks if the Ollama server is running
#   2. Lists downloaded models with sizes
#   3. Shows currently loaded models and memory usage
#   4. Displays GPU/CPU backend info
#   5. Shows recent server logs
#
# Usage:
#   ollama-status.sh                      # Show full status
#   ollama-status.sh --server             # Show server status only
#   ollama-status.sh --models             # List downloaded models
#   ollama-status.sh --loaded             # Show loaded models in memory
#   ollama-status.sh --gpu                # Show GPU/backend info
#   ollama-status.sh --logs               # Show recent server logs
#   ollama-status.sh --json               # Output as JSON

set -euo pipefail

OLLAMA_HOST="${OLLAMA_HOST:-127.0.0.1:11434}"
OLLAMA_MODELS_DIR="${OLLAMA_MODELS:-${HOME}/.ollama/models}"
OLLAMA_LOG_FILE="${HOME}/.ollama/logs/server.log"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -f "$SCRIPT_DIR/lib/common.sh" ]; then
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/lib/common.sh"
else
    _mask_value() { local v="$1" l=${#1}; if [ "$l" -gt 12 ]; then printf '%s' "${v:0:4}****${v: -4} ($l chars)"; elif [ "$l" -gt 0 ]; then printf '%s' "****(masked)"; else printf '%s' "(not set)"; fi; }
    _validate_json() { local f="$1"; if command -v python3 &>/dev/null; then python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$f" 2>/dev/null || return 1; elif command -v jq &>/dev/null; then jq empty "$f" 2>/dev/null || return 1; fi; return 0; }
fi

# ─── Usage ────────────────────────────────────────────────────────────────────

usage() {
    cat << 'USAGE'
Ollama Server — Status & Usage Checker

Usage: ollama-status.sh [options]

Options:
  --server              Show server status only
  --models              List downloaded models with sizes
  --loaded              Show currently loaded models in memory
  --gpu                 Show GPU/backend info
  --logs                Show recent server logs
  --json                Output full status as JSON
  --help, -h            Show this help

Server: $OLLAMA_HOST (override with OLLAMA_HOST env var)
USAGE
    exit 0
}

# ─── Helpers ──────────────────────────────────────────────────────────────────

_ollama_api() {
    local endpoint="$1"
    curl -sf "http://${OLLAMA_HOST}${endpoint}" 2>/dev/null || echo ""
}

_ollama_api_post() {
    local endpoint="$1"
    local data="${2:-{}}"
    curl -sf -X POST "http://${OLLAMA_HOST}${endpoint}" \
        -H "Content-Type: application/json" \
        -d "$data" 2>/dev/null || echo ""
}

_fmt_bytes() {
    local bytes="${1:-0}"
    if [ "$bytes" -ge 1073741824 ] 2>/dev/null; then
        printf '%.1f GB' "$(echo "scale=1;$bytes/1073741824" | bc 2>/dev/null || echo "$bytes")"
    elif [ "$bytes" -ge 1048576 ] 2>/dev/null; then
        printf '%.1f MB' "$(echo "scale=1;$bytes/1048576" | bc 2>/dev/null || echo "$bytes")"
    elif [ "$bytes" -ge 1024 ] 2>/dev/null; then
        printf '%.1f KB' "$(echo "scale=1;$bytes/1024" | bc 2>/dev/null || echo "$bytes")"
    else
        echo "${bytes} B"
    fi
}

# ─── Server Status ────────────────────────────────────────────────────────────

check_server() {
    echo "Ollama Server Status:"
    echo ""

    # Check if server is running
    local version
    version=$(_ollama_api "/api/version")

    if [ -n "$version" ]; then
        echo "  Server: Running"
        echo "  Version: $version"
        echo "  Address: $OLLAMA_HOST"
    else
        echo "  Server: Not running"
        echo "  Address: $OLLAMA_HOST"
        echo ""
        echo "  Start it with: ollama serve"
        echo "  Or as service: brew services start ollama"
        return 1
    fi
    echo ""

    # Check environment variables
    echo "  Environment:"
    echo "    OLLAMA_HOST: $OLLAMA_HOST"
    echo "    OLLAMA_MODELS: ${OLLAMA_MODELS_DIR}"

    local keep_alive="${OLLAMA_KEEP_ALIVE:-5m (default)}"
    echo "    OLLAMA_KEEP_ALIVE: $keep_alive"

    if [ -n "${CUDA_VISIBLE_DEVICES:-}" ]; then
        echo "    CUDA_VISIBLE_DEVICES: $CUDA_VISIBLE_DEVICES"
    fi
    if [ -n "${OLLAMA_DEBUG:-}" ]; then
        echo "    OLLAMA_DEBUG: $OLLAMA_DEBUG"
    fi
    if [ -n "${OLLAMA_NUM_PARALLEL:-}" ]; then
        echo "    OLLAMA_NUM_PARALLEL: $OLLAMA_NUM_PARALLEL"
    fi
}

# ─── Models ───────────────────────────────────────────────────────────────────

check_models() {
    echo "Downloaded Models:"
    echo ""

    local tags
    tags=$(_ollama_api "/api/tags")

    if [ -z "$tags" ]; then
        echo "  Unable to fetch model list."
        echo "  Is the server running? Check: ollama-status.sh --server"
        return
    fi

    python3 -c '
import json, sys

data = json.loads(sys.argv[1])
models = data.get("models", [])

if not models:
    print("  No models downloaded.")
    print("  Download one: ollama pull llama3.2")
    sys.exit(0)

def fmt_bytes(n):
    if n >= 1073741824:
        return f"{n / 1073741824:.1f} GB"
    if n >= 1048576:
        return f"{n / 1048576:.1f} MB"
    return f"{n} B"

total_size = 0
print(f"  {'Model':<40s} {'ID':<14s} {'Size':>10s} {'Modified':<20s}")
print(f"  {'─' * 40} {'─' * 14} {'─' * 10} {'─' * 20}")

for m in sorted(models, key=lambda x: x.get("name", "")):
    name = m.get("name", "unknown")
    digest = m.get("digest", "")[:14]
    size = m.get("size", 0)
    modified = m.get("modified_at", "")[:19]
    total_size += size
    print(f"  {name:<40s} {digest:<14s} {fmt_bytes(size):>10s} {modified:<20s}")

print(f"  {'─' * 40} {'─' * 14} {'─' * 10} {'─' * 20}")
print(f"  Total: {len(models)} model(s), {fmt_bytes(total_size)}")
' "$tags" 2>/dev/null || echo "  Unable to parse model list."
}

# ─── Loaded Models ────────────────────────────────────────────────────────────

check_loaded() {
    echo "Loaded Models (in memory):"
    echo ""

    local ps
    ps=$(_ollama_api "/api/ps")

    if [ -z "$ps" ]; then
        echo "  Unable to fetch loaded model list."
        echo "  Is the server running? Check: ollama-status.sh --server"
        return
    fi

    python3 -c '
import json, sys

data = json.loads(sys.argv[1])
models = data.get("models", [])

if not models:
    print("  No models currently loaded in memory.")
    print("  Models are loaded on first request and stay for OLLAMA_KEEP_ALIVE duration.")
    sys.exit(0)

def fmt_bytes(n):
    if n >= 1073741824:
        return f"{n / 1073741824:.1f} GB"
    if n >= 1048576:
        return f"{n / 1048576:.1f} MB"
    return f"{n} B"

total_vram = 0
print(f"  {'Model':<30s} {'Size':>10s} {'VRAM':>10s} {'Context':>8s} {'Expires':<25s}")
print(f"  {'─' * 30} {'─' * 10} {'─' * 10} {'─' * 8} {'─' * 25}")

for m in sorted(models, key=lambda x: x.get("name", "")):
    name = m.get("name", "unknown")
    size = m.get("size", 0)
    vram = m.get("size_vram", 0)
    ctx = m.get("context_length", "?")
    expires = m.get("expires_at", "")[:24]
    total_vram += vram
    print(f"  {name:<30s} {fmt_bytes(size):>10s} {fmt_bytes(vram):>10s} {str(ctx):>8s} {expires:<25s}")

print(f"  {'─' * 30} {'─' * 10} {'─' * 10} {'─' * 8} {'─' * 25}")
print(f"  Total VRAM used: {fmt_bytes(total_vram)}")
print(f"  Loaded: {len(models)} model(s)")
' "$ps" 2>/dev/null || echo "  Unable to parse loaded model list."
}

# ─── GPU/Backend Info ─────────────────────────────────────────────────────────

check_gpu() {
    echo "GPU / Compute Backend:"
    echo ""

    # Try nvidia-smi first
    if command -v nvidia-smi &>/dev/null; then
        echo "  NVIDIA GPU(s):"
        nvidia-smi --query-gpu=index,name,memory.total,memory.used,memory.free,utilization.gpu,temperature.gpu --format=csv,noheader,nounits 2>/dev/null | while IFS=',' read -r idx name mem_total mem_used mem_free util temp; do
            printf "    GPU %s: %s\n" "$idx" "$name"
            printf "      Memory: %s MB used / %s MB total (%s MB free)\n" "$mem_used" "$mem_total" "$mem_free"
            printf "      Utilization: %s%%\n" "$util"
            printf "      Temperature: %s C\n" "$temp"
        done
    elif command -v metal &>/dev/null || system_profiler SPDisplaysDataType 2>/dev/null | grep -q "Metal"; then
        echo "  Apple Metal GPU:"
        system_profiler SPDisplaysDataType 2>/dev/null | grep -E "Chip|Metal|VRAM" | sed 's/^/    /'
    else
        echo "  No GPU info available."
        echo "  Install nvidia-smi or check Ollama server logs for backend info."
    fi

    echo ""

    # Check Ollama logs for backend info
    if [ -f "$OLLAMA_LOG_FILE" ]; then
        local backend
        backend=$(grep -iE "(cuda|metal|rocm|vulkan|cpu inference)" "$OLLAMA_LOG_FILE" 2>/dev/null | tail -3)
        if [ -n "$backend" ]; then
            echo "  Ollama Backend (from logs):"
            echo "$backend" | sed 's/^/    /'
        fi
    fi
}

# ─── Server Logs ──────────────────────────────────────────────────────────────

check_logs() {
    echo "Recent Server Logs:"
    echo ""

    if [ -f "$OLLAMA_LOG_FILE" ]; then
        tail -20 "$OLLAMA_LOG_FILE" 2>/dev/null | sed 's/^/  /'
    else
        echo "  Log file not found: $OLLAMA_LOG_FILE"
        echo ""
        echo "  Check journalctl if running as systemd service:"
        echo "    journalctl -u ollama.service -n 20"
        echo ""
        echo "  Or on macOS with Homebrew:"
        echo "    brew services log ollama"
    fi
}

# ─── JSON Output ──────────────────────────────────────────────────────────────

output_json() {
    python3 -c '
import json, os, subprocess, sys

result = {
    "server": {"host": os.environ.get("OLLAMA_HOST", "127.0.0.1:11434"), "running": False, "version": None},
    "models": [],
    "loaded": [],
    "gpu": {},
}

host = os.environ.get("OLLAMA_HOST", "127.0.0.1:11434")

try:
    import urllib.request
    r = urllib.request.urlopen(f"http://{host}/api/version", timeout=3)
    result["server"]["running"] = True
    result["server"]["version"] = r.read().decode().strip()
except:
    pass

try:
    import urllib.request
    r = urllib.request.urlopen(f"http://{host}/api/tags", timeout=5)
    data = json.loads(r.read().decode())
    for m in data.get("models", []):
        result["models"].append({
            "name": m.get("name"),
            "size": m.get("size"),
            "digest": m.get("digest"),
            "modified": m.get("modified_at"),
        })
except:
    pass

try:
    import urllib.request
    req = urllib.request.Request(f"http://{host}/api/ps")
    r = urllib.request.urlopen(req, timeout=5)
    data = json.loads(r.read().decode())
    for m in data.get("models", []):
        result["loaded"].append({
            "name": m.get("name"),
            "size": m.get("size"),
            "size_vram": m.get("size_vram"),
            "context_length": m.get("context_length"),
            "expires_at": m.get("expires_at"),
        })
except:
    pass

# GPU info
try:
    r = subprocess.run(["nvidia-smi", "--query-gpu=index,name,memory.total,memory.used",
                        "--format=csv,noheader,nounits"], capture_output=True, text=True, timeout=5)
    if r.returncode == 0:
        gpus = []
        for line in r.stdout.strip().split("\n"):
            parts = [p.strip() for p in line.split(",")]
            if len(parts) >= 4:
                gpus.append({"id": parts[0], "name": parts[1], "mem_total_mb": int(parts[2]), "mem_used_mb": int(parts[3])})
        result["gpu"] = {"type": "nvidia", "gpus": gpus}
except:
    pass

print(json.dumps(result, indent=2))
' 2>/dev/null || echo '{"error": "Unable to generate JSON output"}'
}

# ─── Full Status ──────────────────────────────────────────────────────────────

show_full_status() {
    echo "═══════════════════════════════════════════════════"
    echo "  Ollama — Status Report"
    echo "═══════════════════════════════════════════════════"
    echo ""

    check_server
    echo ""
    check_models
    echo ""
    check_loaded
    echo ""
    check_gpu
    echo ""
    check_logs
}

# ─── Main ─────────────────────────────────────────────────────────────────────

ACTION=""

while [ $# -gt 0 ]; do
    case "$1" in
        --server|--models|--loaded|--gpu|--logs|--json|--full) ACTION="$1"; shift ;;
        --help|-h) usage ;;
        -*) echo "Unknown option: $1"; usage ;;
        *) if [ -z "$ACTION" ]; then ACTION="$1"; fi; shift ;;
    esac
done

case "${ACTION:---full}" in
    --server) check_server ;;
    --models) check_models ;;
    --loaded) check_loaded ;;
    --gpu) check_gpu ;;
    --logs) check_logs ;;
    --json) output_json ;;
    ""|--full) show_full_status ;;
    *) echo "Unknown action: $ACTION"; usage ;;
esac
