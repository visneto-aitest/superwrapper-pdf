#!/usr/bin/env bash
# ai-health.sh - Unified health monitor for all AI CLI tools
#
# Checks:
#   1. CLI installation status
#   2. API keys / credentials validity
#   3. Configuration files
#   4. Alerts on credential issues
#
# Usage:
#   ai-health.sh                       # Full health check
#   ai-health.sh --tools kilo,claude   # Check specific tools
#   ai-health.sh --json                # Output as JSON
#   ai-health.sh --quiet               # Only show errors/warnings
#   ai-health.sh --quick                # Skip API verification (faster)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ALL_TOOLS=("kilo" "opencode" "qwen" "gemini" "claude" "codex")

OUTPUT_MODE="text"
QUIET_MODE=false
QUICK_MODE=false
CHECK_TOOLS=()

# ─── Helpers ────────────────────────────────────────────────────────────────────

_red() { echo -e "\033[0;31m$1\033[0m" >&2; }
_green() { echo -e "\033[0;32m$1\033[0m"; }
_yellow() { echo -e "\033[0;33m$1\033[0m"; }
_blue() { echo -e "\033[0;34m$1\033[0m"; }

_mask_key() { local v="$1" l=${#1}; if [ "$l" -gt 12 ]; then printf '%s' "${v:0:4}****${v: -4}"; elif [ "$l" -gt 0 ]; then printf '%s' "****(masked)"; else printf '%s' "(not set)"; fi; }

usage() {
    cat << 'USAGE'
AI CLI — Health Monitor

Usage: ai-health.sh [options]

Options:
  --tools t1,t2,...     Check specific tools (default: all)
  --json                Output as JSON
  --quiet               Only show errors/warnings
  --quick               Skip API verification (faster)
  --help, -h            Show this help

Tools: kilo, opencode, qwen, gemini, claude, codex
USAGE
    exit 0
}

# ─── Check CLI Installation ──────────────────────────────────────────────────

check_installation() {
    local tool="$1"
    local cmd="$2"
    local install_hint="$3"

    if command -v "$cmd" &>/dev/null; then
        local version
        version=$("$cmd" --version 2>&1 | head -1 || echo "installed")
        echo "  ✅ $tool CLI: installed ($version)"
        return 0
    else
        echo "  ❌ $tool CLI: not installed"
        echo "    Install: $install_hint"
        return 1
    fi
}

# ─── Check Kilo ────────────────────────────────────────────────────────────────

check_kilo() {
    local json_output="$1"
    local result="$( \
        local installed=0
        if command -v kilo &>/dev/null; then
            installed=1
            echo 'installed=true'
            kilo --version 2>&1 | head -1 | sed 's/.*/version=&/' || echo 'version=installed'
        fi

        local cfg="${HOME}/.config/kilo/kilo.jsonc"
        if [ -f "$cfg" ]; then
            echo 'config_exists=true'
        fi

        local accounts_dir="${HOME}/.config/kilo/accounts"
        if [ -d "$accounts_dir" ]; then
            local count
            count=$(find "$accounts_dir" -name "*.env" 2>/dev/null | wc -l | tr -d ' ')
            echo "accounts=$count"
        fi

        local api_key="${KILO_API_KEY:-}"
        if [ -n "$api_key" ]; then
            echo 'has_api_key=true'
        fi
    )"

    if [ "$json_output" = "true" ]; then
        echo "$result" | python3 -c "
import json, sys, os, subprocess
lines = sys.stdin.read().strip().split('\n')
data = {}
for line in lines:
    if '=' in line:
        k, v = line.split('=', 1)
        data[k] = v
print(json.dumps(data))
" 2>/dev/null || echo '{"error": "parse error"}'
    else
        if command -v kilo &>/dev/null; then
            _green "  ✅ Kilo: installed"
        else
            _red "  ❌ Kilo: not installed"
        fi

        if [ -f "${HOME}/.config/kilo/kilo.jsonc" ]; then
            _green "  ✅ Config: ~/.config/kilo/kilo.jsonc"
        else
            _yellow "  ⚠️  Config: not found"
        fi

        local accounts_dir="${HOME}/.config/kilo/accounts"
        if [ -d "$accounts_dir" ]; then
            local count
            count=$(find "$accounts_dir" -name "*.env" 2>/dev/null | wc -l | tr -d ' ')
            if [ "$count" -gt 0 ]; then
                _green "  ✅ Accounts: $count configured"
            else
                _yellow "  ⚠️  Accounts: none configured"
            fi
        else
            _yellow "  ⚠️  Accounts: directory not found"
        fi
    fi
}

# ─── Check OpenCode ───────────────────────────────────────────────────────────

check_opencode() {
    local json_output="$1"

    if command -v opencode &>/dev/null; then
        if [ "$json_output" = "true" ]; then
            echo '{"installed": true}'
        else
            _green "  ✅ OpenCode: installed"
        fi
    else
        if [ "$json_output" = "true" ]; then
            echo '{"installed": false}'
        else
            _red "  ❌ OpenCode: not installed"
        fi
    fi

    local cfg
    for cfg in "${HOME}/.config/opencode/opencode.json" "${HOME}/.opencode.json"; do
        if [ -f "$cfg" ]; then
            if [ "$json_output" = "true" ]; then
                echo '{"config_exists": true}'
            else
                _green "  ✅ Config: $cfg"
            fi
            break
        fi
    done

    if [ "$json_output" != "true" ]; then
        local accounts_dir="${HOME}/.config/opencode/accounts"
        if [ -d "$accounts_dir" ]; then
            local count
            count=$(find "$accounts_dir" -name "*.env" 2>/dev/null | wc -l | tr -d ' ')
            if [ "$count" -gt 0 ]; then
                _green "  ✅ Accounts: $count configured"
            fi
        fi
    fi
}

# ─── Check Qwen ────────────────────────────────────────────────────────────────

check_qwen() {
    local json_output="$1"

    if command -v qwen &>/dev/null; then
        if [ "$json_output" = "true" ]; then
            echo '{"installed": true}'
        else
            _green "  ✅ Qwen: installed"
        fi
    else
        if [ "$json_output" = "true" ]; then
            echo '{"installed": false}'
        else
            _red "  ❌ Qwen: not installed"
        fi
    fi

    local settings="${HOME}/.qwen/settings.json"
    if [ -f "$settings" ]; then
        if [ "$json_output" = "true" ]; then
            echo '{"config_exists": true}'
        else
            _green "  ✅ Config: $settings"
        fi
    else
        if [ "$json_output" != "true" ]; then
            _yellow "  ⚠️  Config: not found (~/.qwen/settings.json)"
        fi
    fi
}

# ─── Check Gemini ──────────────────────────────────────────────────────────────

check_gemini() {
    local json_output="$1"
    local has_issue=false

    if command -v gemini &>/dev/null; then
        if [ "$json_output" = "true" ]; then
            echo '{"installed": true}'
        else
            _green "  ✅ Gemini CLI: installed"
        fi
    else
        if [ "$json_output" = "true" ]; then
            echo '{"installed": false}'
        else
            _red "  ❌ Gemini CLI: not installed"
            has_issue=true
        fi
    fi

    local api_key="${GEMINI_API_KEY:-}"
    local gcloud_auth="${GOOGLE_CLOUD_PROJECT:-}"
    local creds="${GOOGLE_APPLICATION_CREDENTIALS:-}"

    if [ -n "$api_key" ]; then
        if [ "$json_output" = "true" ]; then
            echo '{"has_api_key": true}'
        else
            _green "  ✅ API Key: configured ($(_mask_key "$api_key"))"
        fi
    elif [ -n "$creds" ]; then
        if [ -f "$creds" ]; then
            if [ "$json_output" != "true" ]; then
                _green "  ✅ Service Account: configured"
            fi
        else
            if [ "$json_output" != "true" ]; then
                _red "  ❌ Service Account: file not found ($creds)"
            fi
            has_issue=true
        fi
    elif [ -n "$gcloud_auth" ]; then
        if [ "$json_output" != "true" ]; then
            _green "  ✅ Workspace: $gcloud_auth"
        fi
    else
        if [ "$json_output" != "true" ]; then
            _yellow "  ⚠️  Auth: using OAuth (free tier)"
        fi
    fi
}

# ─── Check Claude ─────────────────────────────────────────────────────────────

check_claude() {
    local json_output="$1"

    if command -v claude &>/dev/null; then
        if [ "$json_output" = "true" ]; then
            echo '{"installed": true}'
        else
            _green "  ✅ Claude Code: installed"
        fi
    else
        if [ "$json_output" = "true" ]; then
            echo '{"installed": false}'
        else
            _red "  ❌ Claude Code: not installed"
        fi
    fi

    local state_file="${HOME}/.claude.json"
    if [ -f "$state_file" ]; then
        if [ "$json_output" = "true" ]; then
            echo '{"state_exists": true}'
        else
            _green "  ✅ State: $state_file"
        fi
    else
        if [ "$json_output" != "true" ]; then
            _yellow "  ⚠️  State: not found (run claude to initialize)"
        fi
    fi

    if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
        if [ "$json_output" != "true" ]; then
            _green "  ✅ API Key: configured ($(_mask_key "$ANTHROPIC_API_KEY"))"
        fi
    elif [ -n "${AWS_ACCESS_KEY_ID:-}" ]; then
        if [ "$json_output" != "true" ]; then
            _green "  ✅ AWS Bedrock: configured"
        fi
    elif [ -n "${CLAUDE_CODE_USE_BEDROCK:-}" ]; then
        if [ "$json_output" != "true" ]; then
            _green "  ✅ AWS Bedrock: enabled"
        fi
    elif [ -n "${CLAUDE_CODE_USE_VERTEX:-}" ]; then
        if [ "$json_output" != "true" ]; then
            _green "  ✅ Vertex AI: enabled"
        fi
    else
        if [ "$json_output" != "true" ]; then
            _yellow "  ⚠️  Auth: using OAuth (subscription)"
        fi
    fi
}

# ─── Check Codex ─────────────────────────────────────────────────────────────

check_codex() {
    local json_output="$1"
    local codex_home="${CODEX_HOME:-${HOME}/.codex}"
    local codex_config="$codex_home/config.toml"
    local codex_auth="$codex_home/auth.json"

    if command -v codex &>/dev/null; then
        if [ "$json_output" = "true" ]; then
            echo '{"installed": true}'
        else
            _green "  ✅ Codex CLI: installed"
        fi
    else
        if [ "$json_output" = "true" ]; then
            echo '{"installed": false}'
        else
            _red "  ❌ Codex CLI: not installed"
        fi
    fi

    if [ -f "$codex_config" ]; then
        if [ "$json_output" = "true" ]; then
            echo '{"config_exists": true}'
        else
            _green "  ✅ Config: $codex_config"
        fi
    else
        if [ "$json_output" != "true" ]; then
            _yellow "  ⚠️  Config: not found"
        fi
    fi

    if [ -f "$codex_auth" ]; then
        if [ "$json_output" != "true" ]; then
            _green "  ✅ Auth: cached"
        fi
    else
        if [ "$json_output" != "true" ]; then
            _yellow "  ⚠️  Auth: not cached (run 'codex login')"
        fi
    fi

    if [ -n "${OPENAI_API_KEY:-}" ]; then
        if [ "$json_output" != "true" ]; then
            _green "  ✅ API Key: configured ($(_mask_key "$OPENAI_API_KEY"))"
        fi
    elif [ -f "$codex_auth" ]; then
        if [ "$json_output" != "true" ]; then
            _green "  ✅ Auth: ChatGPT OAuth"
        fi
    else
        if [ "$json_output" != "true" ]; then
            _yellow "  ⚠️  Auth: none configured"
        fi
    fi
}

# ─── Verify API Keys (when not in quick mode) ─────────────────────────────────

verify_api_keys() {
    if [ "$QUICK_MODE" = "true" ]; then
        echo "  ℹ Skipping API verification (--quick mode)"
        return
    fi

    echo ""
    _blue "  Verifying API keys..."

    # Kilo
    if [ -n "${KILO_API_KEY:-}" ]; then
        echo -n "  Kilo: "
        if [[ "$KILO_API_KEY" =~ ^kilo_ ]] || [[ "$KILO_API_KEY" =~ ^sk- ]]; then
            local resp
            resp=$(curl -s -w "%{http_code}" -o /dev/null \
                -H "Authorization: Bearer $KILO_API_KEY" \
                "https://app.kilo.ai/api/v1/balance" 2>/dev/null) || resp="000"
            case "$resp" in
                200) _green "valid" ;;
                401|403) _red "invalid" ;;
                429) _yellow "rate limited" ;;
                *) _yellow "error ($resp)" ;;
            esac
        else
            _yellow "format unknown"
        fi
    fi

    # OpenAI
    if [ -n "${OPENAI_API_KEY:-}" ]; then
        echo -n "  OpenAI: "
        local resp
        resp=$(curl -s -w "%{http_code}" -o /dev/null \
            -H "Authorization: Bearer $OPENAI_API_KEY" \
            "https://api.openai.com/v1/models" 2>/dev/null) || resp="000"
        case "$resp" in
            200) _green "valid" ;;
            401) _red "invalid" ;;
            429) _yellow "rate limited" ;;
            *) _yellow "error ($resp)" ;;
        esac
    fi

    # Anthropic
    if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
        echo -n "  Anthropic: "
        local resp
        resp=$(curl -s -w "%{http_code}" -o /dev/null \
            -H "x-api-key: $ANTHROPIC_API_KEY" \
            -H "anthropic-version: 2023-06-01" \
            -H "Content-Type: application/json" \
            -d '{"model":"claude-sonnet-4-20250514","max_tokens":1,"messages":[{"role":"user","content":"hi"}]}' \
            "https://api.anthropic.com/v1/messages" 2>/dev/null) || resp="000"
        case "$resp" in
            200) _green "valid" ;;
            401|403) _red "invalid" ;;
            429) _yellow "rate limited" ;;
            *) _yellow "error ($resp)" ;;
        esac
    fi

    # Gemini
    if [ -n "${GEMINI_API_KEY:-}" ]; then
        echo -n "  Gemini: "
        local resp
        resp=$(curl -s -w "%{http_code}" -o /dev/null \
            -H "x-goog-api-key: $GEMINI_API_KEY" \
            "https://generativelanguage.googleapis.com/v1beta/models" 2>/dev/null) || resp="000"
        case "$resp" in
            200) _green "valid" ;;
            400|401) _red "invalid" ;;
            429) _yellow "rate limited" ;;
            *) _yellow "error ($resp)" ;;
        esac
    fi

    # Groq
    if [ -n "${GROQ_API_KEY:-}" ]; then
        echo -n "  Groq: "
        local resp
        resp=$(curl -s -w "%{http_code}" -o /dev/null \
            -H "Authorization: Bearer $GROQ_API_KEY" \
            "https://api.groq.com/openai/v1/models" 2>/dev/null) || resp="000"
        case "$resp" in
            200) _green "valid" ;;
            401) _red "invalid" ;;
            *) _yellow "error ($resp)" ;;
        esac
    fi
}

# ─── Main ─────────────────────────────────────────────────────────────────────

generate_json() {
    python3 -c '
import json, os, subprocess

result = {}

tools = ["kilo", "opencode", "qwen", "gemini", "claude", "codex"]
for tool in tools:
    result[tool] = {"installed": False, "issues": []}

# Check Kilo
try:
    result["kilo"]["installed"] = subprocess.run(["which", "kilo"], capture_output=True).returncode == 0
except: pass
if os.path.exists(os.path.expanduser("~/.config/kilo/kilo.jsonc")):
    result["kilo"]["config"] = "found"
else:
    result["kilo"]["issues"].append("no config")

# Check OpenCode
try:
    result["opencode"]["installed"] = subprocess.run(["which", "opencode"], capture_output=True).returncode == 0
except: pass

# Check Qwen
try:
    result["qwen"]["installed"] = subprocess.run(["which", "qwen"], capture_output=True).returncode == 0
except: pass

# Check Gemini
try:
    result["gemini"]["installed"] = subprocess.run(["which", "gemini"], capture_output=True).returncode == 0
except: pass
if os.environ.get("GEMINI_API_KEY"):
    result["gemini"]["api_key"] = "configured"
if os.environ.get("GOOGLE_CLOUD_PROJECT"):
    result["gemini"]["project"] = os.environ.get("GOOGLE_CLOUD_PROJECT")

# Check Claude
try:
    result["claude"]["installed"] = subprocess.run(["which", "claude"], capture_output=True).returncode == 0
except: pass
if os.path.exists(os.path.expanduser("~/.claude.json")):
    result["claude"]["state"] = "found"

# Check Codex
try:
    result["codex"]["installed"] = subprocess.run(["which", "codex"], capture_output=True).returncode == 0
except: pass
if os.path.exists(os.path.expanduser("~/.codex/config.toml")):
    result["codex"]["config"] = "found"
if os.path.exists(os.path.expanduser("~/.codex/auth.json")):
    result["codex"]["auth"] = "cached"
if os.environ.get("OPENAI_API_KEY"):
    result["codex"]["api_key"] = "configured"

print(json.dumps(result, indent=2))
'
}

while [ $# -gt 0 ]; do
    case "$1" in
        --json) OUTPUT_MODE="json"; shift ;;
        --quiet) QUIET_MODE=true; shift ;;
        --quick) QUICK_MODE=true; shift ;;
        --tools)
            IFS=',' read -ra CHECK_TOOLS <<< "$2"
            shift 2
            ;;
        --help|-h) usage ;;
        -*) echo "❌ Unknown option: $1"; usage ;;
        *) shift ;;
    esac
done

if [ ${#CHECK_TOOLS[@]} -eq 0 ]; then
    CHECK_TOOLS=("${ALL_TOOLS[@]}")
fi

if [ "$OUTPUT_MODE" = "json" ]; then
    generate_json
    exit 0
fi

echo "════════════════════════════════════════════════════════════════════"
echo "  AI CLI — Health Monitor"
echo "════════════════════════════════════════════════════════════════════"
echo ""

for tool in "${CHECK_TOOLS[@]}"; do
    case "$tool" in
        kilo)
            echo "$(_blue "Kilo:")"
            check_kilo false
            ;;
        opencode)
            echo "$(_blue "OpenCode:")"
            check_opencode false
            ;;
        qwen)
            echo "$(_blue "Qwen:")"
            check_qwen false
            ;;
        gemini)
            echo "$(_blue "Gemini:")"
            check_gemini false
            ;;
        claude)
            echo "$(_blue "Claude Code:")"
            check_claude false
            ;;
        codex)
            echo "$(_blue "Codex:")"
            check_codex false
            ;;
        *)
            echo "❌ Unknown tool: $tool"
            ;;
    esac
    echo ""
done

verify_api_keys

echo ""
echo "════════════════════════════════════════════════════════════════════"
echo "  Summary"
echo "════════════════════════════════════════════════════════════════════"
echo ""
echo "  Quick fixes:"
echo "    Kilo:       kilo auth"
echo "    Claude:     claude auth"
echo "    Gemini:     gemini (triggers OAuth)"
echo "    OpenCode:   opencode auth"
echo "    Qwen:       qwen"
echo ""
echo "  Documentation:"
echo "    Kilo:       https://kilo.ai/docs"
echo "    Claude:     https://docs.anthropic.com"
echo "    Gemini:     https://aistudio.google.com"
