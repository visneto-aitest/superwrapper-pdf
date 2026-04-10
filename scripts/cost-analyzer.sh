#!/usr/bin/env bash
# cost-analyzer.sh - Cross-tool cost analysis and forecasting
#
# Features:
#   - Daily/weekly/monthly cost breakdown per tool
#   - Trend analysis and forecasting
#   - Alert when costs exceed thresholds
#   - Compare tool cost-efficiency
#
# Usage:
#   cost-analyzer.sh                       # Full cost analysis
#   cost-analyzer.sh --daily               # Daily breakdown
#   cost-analyzer.sh --weekly              # Weekly breakdown
#   cost-analyzer.sh --monthly             # Monthly breakdown
#   cost-analyzer.sh --trend               # Trend analysis
#   cost-analyzer.sh --forecast            # Forecast next period
#   cost-analyzer.sh --alert 10            # Alert if daily > $10
#   cost-analyzer.sh --compare             # Cost efficiency comparison
#   cost-analyzer.sh --json                # JSON output

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ALL_TOOLS=("kilo" "opencode" "qwen" "gemini" "claude" "codex")

THRESHOLD_DAILY=""
THRESHOLD_WEEKLY=""
THRESHOLD_MONTHLY=""
OUTPUT_JSON=false

usage() {
    cat << 'USAGE'
AI CLI — Cost Analyzer

Usage: cost-analyzer.sh [options]

Options:
  --daily                 Show daily cost breakdown
  --weekly                Show weekly cost breakdown
  --monthly               Show monthly cost breakdown
  --trend                 Show cost trends over time
  --forecast              Forecast next period costs
  --alert <amount>        Alert if daily cost exceeds threshold
  --compare               Compare cost-efficiency across tools
  --json                  Output as JSON
  --threshold-daily $     Set daily alert threshold
  --threshold-weekly $    Set weekly alert threshold
  --threshold-monthly $   Set monthly alert threshold
  --help, -h             Show this help
USAGE
    exit 0
}

# Run a tool's usage script and parse JSON
get_tool_usage() {
    local tool="$1"
    local script="$SCRIPT_DIR/usage-${tool}.sh"

    if [ ! -f "$script" ]; then
        echo "{}"
        return
    fi

    bash "$script" --summary --json 2>/dev/null || echo '{}'
}

# Collect all usage data
collect_all_usage() {
    local result="{}"
    for tool in "${ALL_TOOLS[@]}"; do
        local data
        data=$(get_tool_usage "$tool")
        if [ -n "$data" ] && [ "$data" != "{}" ]; then
            result=$(python3 -c "
import json, sys
try:
    current = json.loads(sys.argv[1])
    tool_data = json.loads(sys.argv[2])
    tool_name = tool_data.get('tool', sys.argv[3])
    current[tool_name] = tool_data
    print(json.dumps(current))
except:
    print(sys.argv[1])
" "$result" "$data" "$tool")
        fi
    done
    echo "$result"
}

# Get detailed sessions with dates
get_sessions_with_dates() {
    local tool="$1"
    local script="$SCRIPT_DIR/usage-${tool}.sh"

    if [ ! -f "$script" ]; then
        echo "[]"
        return
    fi

    bash "$script" --sessions 100 --json 2>/dev/null || echo "[]"
}

# Capitalize first letter
_capitalize() {
    local s="$1"
    printf '%s%s' "$(echo "$s" | cut -c1 | tr '[:lower:]' '[:upper:]')" "$(echo "$s" | cut -c2-)"
}

# Format currency
fmt_cost() {
    local cost="$1"
    if (( $(echo "$cost >= 1" | bc -l 2>/dev/null || echo "0") )); then
        printf '$%.2f' "$cost"
    else
        printf '$%.4f' "$cost"
    fi
}

# Format tokens
fmt_tokens() {
    local n="$1"
    if (( $(echo "$n >= 1000000" | bc -l 2>/dev/null || echo "0") )); then
        printf '%.1fM' "$(echo "scale=1; $n/1000000" | bc -l 2>/dev/null || echo "$n")"
    elif (( $(echo "$n >= 1000" | bc -l 2>/dev/null || echo "0") )); then
        printf '%.1fK' "$(echo "scale=1; $n/1000" | bc -l 2>/dev/null || echo "$n")"
    else
        echo "$n"
    fi
}

# Show daily breakdown
show_daily() {
    echo "════════════════════════════════════════════════════════════════════"
    echo "  Daily Cost Breakdown"
    echo "════════════════════════════════════════════════════════════════════"
    echo ""

    local total_cost=0
    for tool in "${ALL_TOOLS[@]}"; do
        local data
        data=$(get_tool_usage "$tool")
        local cost
        cost=$(echo "$data" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('estimated_cost_usd', 0))" 2>/dev/null || echo "0")

        if [ -n "$cost" ] && [ "$cost" != "0" ]; then
            local tool_name
            tool_name=$(_capitalize "$tool")
            echo "  $tool_name: $(fmt_cost "$cost")"
            total_cost=$(echo "$total_cost + $cost" | bc -l 2>/dev/null || echo "$total_cost")
        fi
    done

    echo ""
    echo "  ─────────────────────────────────────────"
    echo "  Total: $(fmt_cost "$total_cost")"
    echo ""

    if [ -n "$THRESHOLD_DAILY" ]; then
        local threshold="$THRESHOLD_DAILY"
        if (( $(echo "$total_cost > $threshold" | bc -l 2>/dev/null || echo "0") )); then
            echo "  ⚠️  ALERT: Daily cost ($(fmt_cost "$total_cost")) exceeds threshold ($(fmt_cost "$threshold"))"
        else
            echo "  ✅ Daily cost is within threshold"
        fi
    fi
}

# Show weekly breakdown
show_weekly() {
    echo "════════════════════════════════════════════════════════════════════"
    echo "  Weekly Cost Breakdown (estimated from daily avg × 7)"
    echo "════════════════════════════════════════════════════════════════════"
    echo ""

    local total_weekly=0
    for tool in "${ALL_TOOLS[@]}"; do
        local data
        data=$(get_tool_usage "$tool")
        local cost
        cost=$(echo "$data" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('estimated_cost_usd', 0))" 2>/dev/null || echo "0")

        if [ -n "$cost" ] && [ "$cost" != "0" ]; then
            local weekly
            weekly=$(echo "$cost * 7" | bc -l 2>/dev/null || echo "0")
            local tool_name
            tool_name=$(_capitalize "$tool")
            echo "  $tool_name: $(fmt_cost "$weekly")"
            total_weekly=$(echo "$total_weekly + $weekly" | bc -l 2>/dev/null || echo "$total_weekly")
        fi
    done

    echo ""
    echo "  ─────────────────────────────────────────"
    echo "  Estimated Weekly Total: $(fmt_cost "$total_weekly")"
    echo ""

    if [ -n "$THRESHOLD_WEEKLY" ]; then
        if (( $(echo "$total_weekly > $THRESHOLD_WEEKLY" | bc -l 2>/dev/null || echo "0") )); then
            echo "  ⚠️  ALERT: Weekly cost ($(fmt_cost "$total_weekly")) exceeds threshold ($(fmt_cost "$THRESHOLD_WEEKLY"))"
        else
            echo "  ✅ Weekly cost is within threshold"
        fi
    fi
}

# Show monthly breakdown
show_monthly() {
    echo "════════════════════════════════════════════════════════════════════"
    echo "  Monthly Cost Breakdown (estimated from daily avg × 30)"
    echo "════════════════════════════════════════════════════════════════════"
    echo ""

    local total_monthly=0
    for tool in "${ALL_TOOLS[@]}"; do
        local data
        data=$(get_tool_usage "$tool")
        local cost
        cost=$(echo "$data" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('estimated_cost_usd', 0))" 2>/dev/null || echo "0")

        if [ -n "$cost" ] && [ "$cost" != "0" ]; then
            local monthly
            monthly=$(echo "$cost * 30" | bc -l 2>/dev/null || echo "0")
            local tool_name
            tool_name=$(_capitalize "$tool")
            echo "  $tool_name: $(fmt_cost "$monthly")"
            total_monthly=$(echo "$total_monthly + $monthly" | bc -l 2>/dev/null || echo "$total_monthly")
        fi
    done

    echo ""
    echo "  ─────────────────────────────────────────"
    echo "  Estimated Monthly Total: $(fmt_cost "$total_monthly")"
    echo ""

    if [ -n "$THRESHOLD_MONTHLY" ]; then
        if (( $(echo "$total_monthly > $THRESHOLD_MONTHLY" | bc -l 2>/dev/null || echo "0") )); then
            echo "  ⚠️  ALERT: Monthly cost ($(fmt_cost "$total_monthly")) exceeds threshold ($(fmt_cost "$THRESHOLD_MONTHLY"))"
        else
            echo "  ✅ Monthly cost is within threshold"
        fi
    fi
}

# Show trend analysis
show_trend() {
    echo "════════════════════════════════════════════════════════════════════"
    echo "  Cost Trend Analysis"
    echo "════════════════════════════════════════════════════════════════════"
    echo ""

    for tool in "${ALL_TOOLS[@]}"; do
        local data
        data=$(get_tool_usage "$tool")
        local cost tokens sessions
        cost=$(echo "$data" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('estimated_cost_usd', 0))" 2>/dev/null || echo "0")
        tokens=$(echo "$data" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('input_tokens',0) + d.get('output_tokens',0))" 2>/dev/null || echo "0")
        sessions=$(echo "$data" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('sessions', 0))" 2>/dev/null || echo "0")

        if [ -n "$cost" ] && [ "$cost" != "0" ] && [ "$tokens" != "0" ]; then
            local cost_per_token
            cost_per_token=$(echo "scale=6; $cost / $tokens" | bc -l 2>/dev/null || echo "0")
            local cost_per_session
            cost_per_session=$(echo "scale=2; $cost / $sessions" | bc -l 2>/dev/null || echo "0")

            local tool_name
            tool_name=$(_capitalize "$tool")
            echo "  $tool_name:"
            echo "    Sessions: $sessions"
            echo "    Total Cost: $(fmt_cost "$cost")"
            echo "    Tokens: $(fmt_tokens "$tokens")"
            echo "    Cost/Session: $(fmt_cost "$cost_per_session")"
            echo "    Cost/1M Tokens: $(fmt_cost "$(echo "$cost_per_token * 1000000" | bc -l 2>/dev/null || echo "0")")"
            echo ""
        fi
    done
}

# Show forecast
show_forecast() {
    echo "════════════════════════════════════════════════════════════════════"
    echo "  Cost Forecasting"
    echo "════════════════════════════════════════════════════════════════════"
    echo ""

    local total_daily=0
    local tool_costs=""
    for tool in "${ALL_TOOLS[@]}"; do
        local data
        data=$(get_tool_usage "$tool")
        local cost
        cost=$(echo "$data" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('estimated_cost_usd', 0))" 2>/dev/null || echo "0")
        if [ -n "$cost" ] && [ "$cost" != "0" ]; then
            total_daily=$(echo "$total_daily + $cost" | bc -l 2>/dev/null || echo "$total_daily")
        fi
    done

    local weekly_forecast monthly_forecast
    weekly_forecast=$(echo "$total_daily * 7" | bc -l 2>/dev/null || echo "0")
    monthly_forecast=$(echo "$total_daily * 30" | bc -l 2>/dev/null || echo "0")
    local yearly_forecast
    yearly_forecast=$(echo "$total_daily * 365" | bc -l 2>/dev/null || echo "0")

    echo "  Based on current daily rate: $(fmt_cost "$total_daily")"
    echo ""
    echo "  Forecast:"
    echo "    Next 7 days:   $(fmt_cost "$weekly_forecast")"
    echo "    Next 30 days:  $(fmt_cost "$monthly_forecast")"
    echo "    Next 365 days: $(fmt_cost "$yearly_forecast")"
    echo ""

    if [ -n "$THRESHOLD_DAILY" ]; then
        if (( $(echo "$total_cost > $threshold" | bc -l 2>/dev/null || echo "0") )); then
            echo "  ⚠️  ALERT: Daily cost ($(fmt_cost "$total_cost")) exceeds threshold ($(fmt_cost "$threshold"))"
        else
            echo "  ✅ Daily cost is within threshold"
        fi
    fi

    echo ""
    echo "  Note: Costs shown are from session data. Actual provider billing"
    echo "        may differ. Check provider dashboards for real costs."
}

# Compare cost efficiency
show_compare() {
    echo "════════════════════════════════════════════════════════════════════"
    echo "  Cost Efficiency Comparison"
    echo "════════════════════════════════════════════════════════════════════"
    echo ""

    printf "  %-12s %10s %12s %12s %12s\n" "Tool" "Total Cost" "Tokens" "Cost/1M" "Efficiency"
    echo "  %-12s %10s %12s %12s %12s" "------------" "----------" "------------" "------------" "------------"

    local tool_data=()
    for tool in "${ALL_TOOLS[@]}"; do
        local data
        data=$(get_tool_usage "$tool")
        local cost tokens
        cost=$(echo "$data" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('estimated_cost_usd', 0))" 2>/dev/null || echo "0")
        tokens=$(echo "$data" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('input_tokens',0) + d.get('output_tokens',0))" 2>/dev/null || echo "0")

        if [ -n "$cost" ] && [ "$cost" != "0" ] && [ "$tokens" != "0" ] && [ "$tokens" -gt 0 ] 2>/dev/null; then
            local cost_per_m
            cost_per_m=$(echo "scale=2; ($cost / $tokens) * 1000000" | bc -l 2>/dev/null || echo "0")
            local name
            name=$(_capitalize "$tool")
            printf "  %-12s %10s %12s %12s %12s\n" "$name" "$(fmt_cost "$cost")" "$(fmt_tokens "$tokens")" "$(fmt_cost "$cost_per_m")" "⭐"
        fi
    done | sort -t'$' -k2 -n -r

    echo ""
    echo "  Note: Efficiency = ⭐ means better cost per million tokens"
}

# Show full analysis
show_full() {
    show_daily
    echo ""
    show_weekly
    echo ""
    show_monthly
    echo ""
    show_trend
    echo ""
    show_forecast
}

# JSON output
output_json() {
    python3 -c "
import json
import subprocess
import os

result = {
    'tools': {},
    'totals': {
        'daily': 0,
        'weekly_estimate': 0,
        'monthly_estimate': 0,
        'yearly_estimate': 0
    }
}

tools = ['kilo', 'opencode', 'qwen', 'gemini', 'claude', 'codex']
script_dir = os.path.dirname(os.path.realpath('$0'))

for tool in tools:
    script = f'{script_dir}/usage-{tool}.sh'
    if not os.path.isfile(script):
        continue
    try:
        r = subprocess.run(['bash', script, '--summary', '--json'], capture_output=True, text=True, timeout=10)
        if r.returncode == 0 and r.stdout.strip():
            data = json.loads(r.stdout.strip())
            cost = data.get('estimated_cost_usd', 0)
            result['tools'][tool] = data
            result['totals']['daily'] += cost
    except:
        pass

result['totals']['weekly_estimate'] = result['totals']['daily'] * 7
result['totals']['monthly_estimate'] = result['totals']['daily'] * 30
result['totals']['yearly_estimate'] = result['totals']['daily'] * 365

print(json.dumps(result, indent=2))
" 2>/dev/null || echo '{"error": "Unable to generate JSON"}'
}

# Main
ACTION="full"

while [ $# -gt 0 ]; do
    case "$1" in
        --daily) ACTION="daily"; shift ;;
        --weekly) ACTION="weekly"; shift ;;
        --monthly) ACTION="monthly"; shift ;;
        --trend) ACTION="trend"; shift ;;
        --forecast) ACTION="forecast"; shift ;;
        --compare) ACTION="compare"; shift ;;
        --alert)
            THRESHOLD_DAILY="${2:-}"
            ACTION="alert"
            shift 2
            ;;
        --threshold-daily)
            THRESHOLD_DAILY="${2:-}"
            shift 2
            ;;
        --threshold-weekly)
            THRESHOLD_WEEKLY="${2:-}"
            shift 2
            ;;
        --threshold-monthly)
            THRESHOLD_MONTHLY="${2:-}"
            shift 2
            ;;
        --json) OUTPUT_JSON=true; shift ;;
        --help|-h) usage ;;
        -*) echo "❌ Unknown option: $1"; usage ;;
        *) shift ;;
    esac
done

if [ "$OUTPUT_JSON" = true ]; then
    output_json
    exit 0
fi

case "$ACTION" in
    daily) show_daily ;;
    weekly) show_weekly ;;
    monthly) show_monthly ;;
    trend) show_trend ;;
    forecast) show_forecast ;;
    compare) show_compare ;;
    alert)
        show_daily
        if [ -n "$THRESHOLD_DAILY" ]; then
            echo ""
            read -p "Press Enter to acknowledge..."
        fi
        ;;
    full) show_full ;;
esac
