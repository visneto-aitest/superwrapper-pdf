#!/usr/bin/env bash
# usage-all.sh - Cross-tool token usage report for all 5 AI CLI tools
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ALL_TOOLS=("kilo" "opencode" "qwen" "gemini" "claude")

usage() {
    cat << 'USAGE'
AI CLI — Cross-Tool Token Usage Report

Usage: usage-all.sh [options]

Options:
  --summary             One-line summary per tool (default)
  --by-range            Breakdown by time period across all tools
  --details             Full detail: summary + sessions per tool
  --tools t1,t2,...     Comma-separated tool list (default: all 5)
  --sessions [N]        Include session detail (N per tool, default 10)
  --by-profile          Group by account/profile across tools
  --range <period>      Filter to time period: today|week|month|6months|all
  --json                Output as JSON
  --help, -h            Show this help

Tools: kilo, opencode, qwen, gemini, claude
USAGE
    exit 0
}

# ─── Main ─────────────────────────────────────────────────────────────────────

ACTION=""
MAX_SESSIONS=10
TOOLS=("${ALL_TOOLS[@]}")
OUTPUT_MODE="text"
TIME_RANGE=""

while [ $# -gt 0 ]; do
    case "$1" in
        --summary) ACTION="summary"; shift ;;
        --by-range) ACTION="by-range"; shift ;;
        --details) ACTION="details"; shift ;;
        --by-profile) ACTION="by-profile"; shift ;;
        --tools)
            IFS=',' read -ra TOOLS <<< "$2"
            shift 2
            ;;
        --sessions)
            ACTION="details"
            if [ -n "${2:-}" ] && [[ "$2" =~ ^[0-9]+$ ]]; then
                MAX_SESSIONS="$2"; shift 2
            else
                shift
            fi
            ;;
        --range) TIME_RANGE="${2:-}"; shift 2 ;;
        --json) OUTPUT_MODE="json"; shift ;;
        --help|-h) usage ;;
        -*) echo "❌ Unknown option: $1"; usage ;;
        *) shift ;;
    esac
done

for t in "${TOOLS[@]}"; do
    case "$t" in
        kilo|opencode|qwen|gemini|claude) ;;
        *) echo "❌ Unknown tool: $t"; echo "Valid: kilo, opencode, qwen, gemini, claude"; exit 1 ;;
    esac
done

# ─── Summary table ───────────────────────────────────────────────────────────

show_summary_table() {
    python3 - "$SCRIPT_DIR" "$OUTPUT_MODE" "$TIME_RANGE" "${TOOLS[@]}" << 'PYEOF'
import json, os, sys, subprocess

script_dir = sys.argv[1]
output_mode = sys.argv[2]
time_range = sys.argv[3] if len(sys.argv) > 3 else ""
tools = sys.argv[4:]

results = []
for tool in tools:
    script = os.path.join(script_dir, f"usage-{tool}.sh")
    if not os.path.isfile(script):
        results.append({"tool": tool, "status": "script_not_found"})
        continue
    try:
        cmd = ["bash", script, "--summary", "--json"]
        if time_range:
            cmd += ["--range", time_range]
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=15)
        if r.returncode == 0 and r.stdout.strip():
            data = json.loads(r.stdout.strip())
            results.append(data)
        else:
            results.append({"tool": tool, "status": "no_data"})
    except Exception as e:
        results.append({"tool": tool, "status": "error", "error": str(e)})

if output_mode == "json":
    print(json.dumps(results, indent=2))
else:
    grand_input = grand_output = grand_cache = grand_total = grand_cost = 0
    active_tools = 0

    header = "  {:<12s} {:>10s} {:>10s} {:>10s} {:>10s} {:>12s}".format(
        "Tool", "Input", "Output", "Cache", "Total", "Est. Cost")
    sep = "  " + "\u2500" * 12 + " " + "\u2500" * 10 + " " + "\u2500" * 10 + " " + "\u2500" * 10 + " " + "\u2500" * 10 + " " + "\u2500" * 12

    if time_range:
        range_labels = {"today": "Today", "week": "Last 7 days", "month": "Last 30 days", "6months": "Last 6 months", "all": "All time"}
        label = range_labels.get(time_range, time_range)
        print(f"  AI CLI Usage \u2014 {label}")
    else:
        print("  AI CLI Usage Summary")
    print(header)
    print(sep)

    for d in results:
        if d.get("status") in ("script_not_found", "no_data", "error"):
            continue
        tool = d.get("tool", "?")
        inp = d.get("input_tokens", d.get("total_input_tokens", 0))
        out = d.get("output_tokens", d.get("total_output_tokens", 0))
        cr = d.get("cache_read", d.get("cache_read_tokens", 0))
        cc = d.get("cache_write", d.get("cache_creation", d.get("cache_write_tokens", 0)))
        cache = cr + cc
        total = inp + out + cr + cc
        cost = d.get("estimated_cost_usd", 0)
        if cost > 1000:
            cost = cost / 1_000_000
        grand_input += inp; grand_output += out; grand_cache += cache; grand_total += total; grand_cost += cost
        active_tools += 1

        def fmt(n):
            if n >= 1_000_000:
                return f"{n / 1_000_000:.1f}M"
            if n >= 1_000:
                return f"{n / 1_000:.1f}K"
            return str(n)

        tool_name = {"kilo": "Kilo", "opencode": "OpenCode", "qwen": "Qwen", "gemini": "Gemini", "claude": "Claude"}.get(tool, tool)
        print("  {:<12s} {:>10s} {:>10s} {:>10s} {:>10s} {:>12s}".format(
            tool_name, fmt(inp), fmt(out), fmt(cache), fmt(total), "${:.4f}".format(cost)))

    print()
    def fmt(n):
        if n >= 1_000_000:
            return f"{n / 1_000_000:.1f}M"
        if n >= 1_000:
            return f"{n / 1_000:.1f}K"
        return str(n)

    print("  {:<12s} {:>10s} {:>10s} {:>10s} {:>10s} {:>12s}".format(
        f"TOTAL ({active_tools})", fmt(grand_input), fmt(grand_output),
        fmt(grand_cache), fmt(grand_total), "${:.4f}".format(grand_cost)))
    print()
    print("  Note: Costs are estimates based on local session data.")
    print("        Actual billing depends on provider and plan.")
PYEOF
}

# ─── By-range: cross-tool time period breakdown ──────────────────────────────

show_by_range() {
    python3 - "$SCRIPT_DIR" "${TOOLS[@]}" << 'PYEOF'
import json, os, sys, subprocess

script_dir = sys.argv[1]
tools = sys.argv[2:]

# Collect per-tool, per-range data
all_data = {}
for tool in tools:
    script = os.path.join(script_dir, f"usage-{tool}.sh")
    if not os.path.isfile(script):
        continue
    try:
        r = subprocess.run(
            ["bash", script, "--by-range", "--json"],
            capture_output=True, text=True, timeout=15,
        )
        if r.returncode == 0 and r.stdout.strip():
            all_data[tool] = json.loads(r.stdout.strip())
    except Exception:
        pass

if not all_data:
    print("  No usage data found for any tool.")
    sys.exit(0)

# Get range labels from first tool's data
first_tool = list(all_data.values())[0]
ranges = [(r["range"], r["range_label"]) for r in first_tool]

tool_labels = {"kilo": "Kilo", "opencode": "OpenCode", "qwen": "Qwen", "gemini": "Gemini", "claude": "Claude"}

print("  AI CLI Usage by Time Period (across all tools)")
print()

# Show per-tool breakdown by range
for tool in tools:
    if tool not in all_data:
        continue
    label = tool_labels.get(tool, tool)
    print(f"  {label}:")
    print("  {:<18s} {:>8s} {:>10s} {:>10s} {:>10s} {:>10s}".format(
        "Period", "Sessions", "Input", "Output", "Cache", "Est. Cost"))
    print("  " + "\u2500" * 18 + " " + "\u2500" * 8 + " " + "\u2500" * 10 + " " + "\u2500" * 10 + " " + "\u2500" * 10 + " " + "\u2500" * 10)

    for entry in all_data[tool]:
        def fmt(n):
            if n >= 1_000_000:
                return f"{n / 1_000_000:.1f}M"
            if n >= 1_000:
                return f"{n / 1_000:.1f}K"
            return str(n)
        print("  {:<18s} {:>8d} {:>10s} {:>10s} {:>10s} ${:>9.4f}".format(
            entry["range_label"],
            entry.get("sessions", entry.get("entries", 0)),
            fmt(entry["input"]),
            fmt(entry["output"]),
            fmt(entry.get("cache_read", 0) + entry.get("cache_write", 0) + entry.get("cached", 0) + entry.get("cache_creation", 0)),
            entry.get("cost_usd", 0),
        ))
    print()

# Cross-tool totals per range
print("  Cross-Tool Totals:")
print("  {:<18s} {:>8s} {:>10s} {:>10s} {:>10s} {:>10s}".format(
    "Period", "Sessions", "Input", "Output", "Cache", "Est. Cost"))
print("  " + "\u2500" * 18 + " " + "\u2500" * 8 + " " + "\u2500" * 10 + " " + "\u2500" * 10 + " " + "\u2500" * 10 + " " + "\u2500" * 10)

for range_key, range_label in ranges:
    total_sessions = total_input = total_output = total_cache = total_cost = 0
    for tool in tools:
        if tool not in all_data:
            continue
        for entry in all_data[tool]:
            if entry["range"] == range_key:
                total_sessions += entry.get("sessions", entry.get("entries", 0))
                total_input += entry["input"]
                total_output += entry["output"]
                total_cache += entry.get("cache_read", 0) + entry.get("cache_write", 0) + entry.get("cached", 0) + entry.get("cache_creation", 0)
                total_cost += entry.get("cost_usd", 0)

    def fmt(n):
        if n >= 1_000_000:
            return f"{n / 1_000_000:.1f}M"
        if n >= 1_000:
            return f"{n / 1_000:.1f}K"
        return str(n)

    print("  {:<18s} {:>8d} {:>10s} {:>10s} {:>10s} ${:>9.4f}".format(
        range_label, total_sessions,
        fmt(total_input), fmt(total_output), fmt(total_cache),
        total_cost))
PYEOF
}

# ─── By profile ──────────────────────────────────────────────────────────────

show_by_profile() {
    echo "════════════════════════════════════════════════════════════════════"
    echo "  AI CLI — Usage by Account/Profile"
    echo "════════════════════════════════════════════════════════════════════"
    echo ""

    declare -A all_accounts=()

    for accounts_dir in \
        "$HOME/.config/kilo/accounts" \
        "$HOME/.config/opencode/accounts" \
        "$HOME/.config/qwen/accounts" \
        "$HOME/.config/gemini/accounts"; do
        if [ -d "$accounts_dir" ]; then
            shopt -s nullglob 2>/dev/null || true
            for f in "$accounts_dir"/*.env; do
                [ -f "$f" ] || continue
                all_accounts["$(basename "$f" .env)"]=1
            done
            shopt -u nullglob 2>/dev/null || true
        fi
    done

    if [ -d "$HOME/.claude-profiles" ]; then
        shopt -s nullglob 2>/dev/null || true
        for d in "$HOME/.claude-profiles"/*/; do
            [ -d "$d" ] || continue
            all_accounts["$(basename "$d")"]=1
        done
        shopt -u nullglob 2>/dev/null || true
    fi

    if [ ${#all_accounts[@]} -eq 0 ]; then
        echo "  No accounts found across any tool."
        return
    fi

    for acct in $(printf '%s\n' "${!all_accounts[@]}" | sort); do
        echo "  Account: $acct"
        local tools_found=()
        [ -f "$HOME/.config/kilo/accounts/$acct.env" ] && tools_found+=("kilo")
        [ -f "$HOME/.config/opencode/accounts/$acct.env" ] && tools_found+=("opencode")
        [ -f "$HOME/.config/qwen/accounts/$acct.env" ] && tools_found+=("qwen")
        [ -f "$HOME/.config/gemini/accounts/$acct.env" ] && tools_found+=("gemini")
        [ -d "$HOME/.claude-profiles/$acct" ] && tools_found+=("claude")
        if [ ${#tools_found[@]} -gt 0 ]; then
            printf "    %-12s %s\n" "Tools:" "$(IFS=', '; echo "${tools_found[*]}")"
        else
            printf "    %-12s %s\n" "Tools:" "(not configured)"
        fi
        echo ""
    done
}

# ─── Details (summary + sessions per tool) ──────────────────────────────────

show_details() {
    show_summary_table

    for tool in "${TOOLS[@]}"; do
        echo ""
        script="$SCRIPT_DIR/usage-${tool}.sh"
        if [ -f "$script" ]; then
            cmd=("$script" "--sessions" "$MAX_SESSIONS")
            [ -n "$TIME_RANGE" ] && cmd+=("--range" "$TIME_RANGE")
            bash "${cmd[@]}" 2>/dev/null || true
        fi
    done
}

# ─── Run ─────────────────────────────────────────────────────────────────────

case "${ACTION:-summary}" in
    summary)
        if [ "$OUTPUT_MODE" != "json" ]; then
            echo "════════════════════════════════════════════════════════════════════"
            echo "  AI CLI — Token Usage Report"
            echo "════════════════════════════════════════════════════════════════════"
            echo ""
        fi
        show_summary_table
        ;;
    by-range)
        show_by_range
        ;;
    details)
        if [ "$OUTPUT_MODE" != "json" ]; then
            echo "════════════════════════════════════════════════════════════════════"
            echo "  AI CLI — Token Usage Report (Detailed)"
            echo "════════════════════════════════════════════════════════════════════"
            echo ""
        fi
        show_details
        ;;
    by-profile)
        show_by_profile
        ;;
esac
