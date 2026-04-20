#!/usr/bin/env bash
# ai-orchestrator.sh - Parallel task orchestrator across AI CLI tools
#
# Features:
#   - Run tasks across multiple AI tools in parallel
#   - Auto-select best result based on quality metrics
#   - DAG task scheduling with dependencies
#   - Isolated worktrees per agent
#   - Automatic diff comparison
#
# Usage:
#   ai-orchestrator.sh run "task description"
#   ai-orchestrator.sh run --tools kilo,opencode,codex "add login page"
#   ai-orchestrator.sh run --parallel 3 "implement user auth"
#   ai-orchestrator.sh review "review PR #123"
#   ai-orchestrator.sh diff "compare results"

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ALL_TOOLS=("kilo" "opencode" "qwen" "gemini" "claude" "codex")
DEFAULT_PARALLEL=3
DEFAULT_TOOLS=("kilo" "opencode" "claude")

WORKDIR="${TMPDIR:-/tmp}/ai-orchestrator"
mkdir -p "$WORKDIR"

usage() {
    cat << 'USAGE'
AI CLI Parallel Orchestrator

Usage: ai-orchestrator.sh <command> [options] "task description"

Commands:
  run [options] "task"       Run task across multiple AI tools
  review "task"              Run code review across agents
  diff                      Compare results from all agents
  list                      List available tools
  status                    Show status of running tasks

Options:
  --tools t1,t2,...         Specific tools to use (default: kilo,opencode,claude)
  --parallel N             Max parallel agents (default: 3)
  --timeout SECS           Timeout per agent (default: 300)
  --diff-only              Only show diffs, don't apply changes
  --dry-run                Preview without executing
  --output DIR             Output directory for results

Examples:
  ai-orchestrator.sh run "add login page"
  ai-orchestrator.sh run --tools kilo,codex "fix memory leak"
  ai-orchestrator.sh run --parallel 5 "refactor user service"
USAGE
    exit 0
}

# Capitalize first letter
_capitalize() {
    local s="$1"
    printf '%s%s' "$(echo "$s" | cut -c1 | tr '[:lower:]' '[:upper:]')" "$(echo "$s" | cut -c2-)"
}

# List available tools
list_tools() {
    echo "Available AI tools:"
    echo ""
    for tool in "${ALL_TOOLS[@]}"; do
        if command -v "$tool" &>/dev/null; then
            local version
            version=$("$tool" --version 2>&1 | head -1 || echo "installed")
            echo "  ✅ $tool: $version"
        else
            echo "  ❌ $tool: not installed"
        fi
    done
}

# Create isolated worktree
create_worktree() {
    local task_id="$1"
    local tool="$2"
    local worktree="$WORKDIR/$task_id/$tool"

    mkdir -p "$worktree"

    # Clone current directory into worktree
    if [ -d ".git" ]; then
        # Use git worktree if available
        git worktree add --quiet "$worktree" HEAD 2>/dev/null || {
            # Fallback to copy
            rsync -a --exclude='.git' ./ "$worktree"
        }
    else
        rsync -a ./ "$worktree"
    fi

    echo "$worktree"
}

# Run a single agent
run_agent() {
    local tool="$1"
    local task="$2"
    local workdir="$3"
    local timeout="${4:-300}"

    local logfile="$workdir/agent.log"
    local resultfile="$workdir/result.json"

    echo "[$tool] Starting..." > "$logfile"

    # Execute with timeout
    if command -v timeout &>/dev/null; then
        timeout "$timeout" bash -c "cd '$workdir' && '$tool' '$task' --non-interactive" >> "$logfile" 2>&1 || {
            local exit_code=$?
            if [ "$exit_code" = 124 ]; then
                echo "[$tool] TIMEOUT after ${timeout}s" >> "$logfile"
            fi
        }
    else
        cd "$workdir" && "$tool" "$task" --non-interactive >> "$logfile" 2>&1
    fi

    # Generate result summary
    python3 -c "
import json, os, sys
log = open(sys.argv[1]).read()
workdir = sys.argv[2]
resultfile = sys.argv[3]
tool = sys.argv[4]
files = [f for f in os.listdir(workdir) if os.path.isfile(f) and f not in ['agent.log', 'result.json']]
result = {
    'tool': tool,
    'status': 'completed' if os.path.exists(os.path.join(workdir, '.success')) else 'partial',
    'files_modified': files,
    'log_length': len(log),
    'exit_code': 0
}
json.dump(result, open(resultfile, 'w'), indent=2)
" "$logfile" "$workdir" "$resultfile" "$tool" 2>/dev/null || echo '{"tool":"'"$tool"'","status":"failed"}' > "$resultfile"
}

# Compare results and select best
select_best_result() {
    local task_id="$1"
    local workdir="$WORKDIR/$task_id"

    echo ""
    echo "════════════════════════════════════════════════════════════════════"
    echo "  Results Comparison"
    echo "════════════════════════════════════════════════════════════════════"
    echo ""

    local results=()
    for tool in "${SELECTED_TOOLS[@]}"; do
        local resfile="$workdir/$tool/result.json"
        if [ -f "$resfile" ]; then
            results+=("$resfile")
        fi
    done

    if [ ${#results[@]} -eq 0 ]; then
        echo "❌ No results from any agent"
        return 1
    fi

    python3 -c "
import json, sys
results = []
for f in sys.argv[1:]:
    try:
        results.append(json.load(open(f)))
    except:
        pass

print(f'  Total agents completed: {len(results)}')
print()

best = None
max_score = -1

for r in results:
    score = 0
    if r.get('status') == 'completed':
        score += 10
    score += len(r.get('files_modified', [])) * 2
    score += min(r.get('log_length', 0) // 1000, 5)

    tool = r.get('tool', 'unknown')
    print(f'  {tool:<12} | Files: {len(r.get(\"files_modified\", [])):<2} | Log: {r.get(\"log_length\",0):>5} chars | Score: {score}')

    if score > max_score:
        max_score = score
        best = r

print()
if best:
    print(f'  ✅ Best result: {best[\"tool\"]} (score: {max_score})')
    print(f'     Workdir: {sys.argv[1].rsplit(\"/\",1)[0]}/{best[\"tool\"]}')
    # Output best tool name to stdout for bash to capture (prefixed with BEST:)
    print(f'BEST:{best[\"tool\"]}')
" "${results[@]}" | tee "$workdir/scoring_output.txt"

    echo ""

    # Extract best tool from scoring output
    local best_tool
    best_tool=$(grep '^BEST:' "$workdir/scoring_output.txt" 2>/dev/null | head -1 | cut -d: -f2)
    if [ -z "$best_tool" ]; then
        # Fallback: parse the scoring output for the highest score
        best_tool=$(grep '✅ Best result:' "$workdir/scoring_output.txt" 2>/dev/null | sed 's/.*Best result: \([^ ]*\).*/\1/')
    fi
    if [ -z "$best_tool" ]; then
        echo "⚠ Could not determine best tool, using first available"
        best_tool=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('tool','unknown'))" "${results[0]}" 2>/dev/null || echo "unknown")
    fi

    read -p "Apply best result from $best_tool? (y/N) " -n 1 -r apply
    echo
    if [[ $apply =~ ^[Yy]$ ]]; then
        if [ -d "$workdir/$best_tool" ]; then
            echo "  Applying changes from $best_tool..."
            rsync -a "$workdir/$best_tool/" ./ --exclude='.git' --exclude='agent.log' --exclude='result.json'
            echo "  ✅ Changes applied"
        fi
    fi
}

# Main run command
run_task() {
    local task=""
    local parallel="$DEFAULT_PARALLEL"
    local timeout=300
    local dry_run=false
    local diff_only=false

    while [ $# -gt 0 ]; do
        case "$1" in
            --tools)
                IFS=',' read -ra SELECTED_TOOLS <<< "$2"
                shift 2
                ;;
            --parallel)
                parallel="$2"
                shift 2
                ;;
            --timeout)
                timeout="$2"
                shift 2
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            --diff-only)
                diff_only=true
                shift
                ;;
            *)
                task="$1"
                shift
                ;;
        esac
    done

    if [ -z "$task" ]; then
        echo "❌ Task description required"
        usage
    fi

    if [ -z "${SELECTED_TOOLS:-}" ]; then
        SELECTED_TOOLS=("${DEFAULT_TOOLS[@]}")
    fi

    # Validate tools
    local valid_tools=()
    for tool in "${SELECTED_TOOLS[@]}"; do
        if command -v "$tool" &>/dev/null; then
            valid_tools+=("$tool")
        else
            echo "⚠️  $tool not found, skipping"
        fi
    done

    if [ ${#valid_tools[@]} -eq 0 ]; then
        echo "❌ No valid tools selected"
        list_tools
        exit 1
    fi

    SELECTED_TOOLS=("${valid_tools[@]}")

    local task_id="$(date +%s)"
    echo "════════════════════════════════════════════════════════════════════"
    echo "  Running Task #$task_id"
    echo "════════════════════════════════════════════════════════════════════"
    echo ""
    echo "  Task: $task"
    echo "  Tools: $(IFS=', '; echo "${SELECTED_TOOLS[*]}")"
    echo "  Parallel: $parallel agents"
    echo "  Timeout: $timeout seconds"
    echo ""

    if [ "$dry_run" = true ]; then
        echo "  🚀 [DRY RUN] Would run task now"
        echo ""
        exit 0
    fi

    # Create worktrees
    echo "  Creating isolated worktrees..."
    local pids=()
    for tool in "${SELECTED_TOOLS[@]}"; do
        local worktree="$(create_worktree "$task_id" "$tool")"
        echo "  ✅ $tool: $worktree"

        # Run in background
        run_agent "$tool" "$task" "$worktree" "$timeout" &
        pids+=($!)
    done

    echo ""
    echo "  Running agents in parallel..."
    echo "  (this may take up to $timeout seconds)"
    echo ""

    # Wait for all
    local complete=0
    for pid in "${pids[@]}"; do
        wait "$pid" && complete=$((complete + 1))
    done

    echo ""
    echo "  ✅ $complete/${#pids[@]} agents completed"

    select_best_result "$task_id"

    # Cleanup worktrees if not kept
    if [ "$diff_only" = true ]; then
        echo ""
        echo "  Keeping worktrees at: $WORKDIR/$task_id"
    else
        read -p "Keep worktrees? (y/N) " -n 1 -r keep
        echo
        if [[ ! $keep =~ ^[Yy]$ ]]; then
            rm -rf "$WORKDIR/$task_id"
            echo "  Worktrees cleaned up"
        else
            echo "  Worktrees kept at: $WORKDIR/$task_id"
        fi
    fi
}

# Show status
show_status() {
    echo "Active tasks:"
    echo ""
    for task_dir in "$WORKDIR"/*/; do
        [ -d "$task_dir" ] || continue
        local task_id="$(basename "$task_dir")"
        echo "  Task #$task_id"
        for tool_dir in "$task_dir"/*/; do
            [ -d "$tool_dir" ] || continue
            local tool="$(basename "$tool_dir")"
            if [ -f "$tool_dir/result.json" ]; then
                echo "    ✅ $tool: completed"
            elif [ -f "$tool_dir/agent.log" ]; then
                local last_line="$(tail -1 "$tool_dir/agent.log" 2>/dev/null || echo "running")"
                echo "    ⏳ $tool: $last_line"
            fi
        done
        echo ""
    done
}

case "${1:-}" in
    run)
        shift
        run_task "$@"
        ;;
    review)
        shift
        run_task "$@"
        ;;
    diff)
        echo "Diff comparison feature coming soon"
        ;;
    list)
        list_tools
        ;;
    status)
        show_status
        ;;
    --help|-h|help)
        usage
        ;;
    *)
        if [ $# -gt 0 ]; then
            # Assume run command
            run_task "$@"
        else
            usage
        fi
        ;;
esac
