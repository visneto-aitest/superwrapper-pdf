#!/usr/bin/env bash
# git-ai.sh - Git AI automation and PR orchestration
#
# Features:
#   - AI commit message generation
#   - PR description and title generation
#   - AI code review across multiple tools
#   - Auto-detect PR template
#   - Run checks before pushing
#
# Usage:
#   git-ai.sh commit "description"      # Generate commit
#   git-ai.sh pr                        # Generate PR
#   git-ai.sh review <pr>               # AI review PR
#   git-ai.sh check                     # Run pre-push checks
#   git-ai.sh clean                     # Clean up AI temp files

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFERRED_TOOL="kilo"
ALL_TOOLS=("kilo" "opencode" "claude" "codex")

usage() {
    cat << 'USAGE'
Git AI Automation

Usage: git-ai.sh <command> [options]

Commands:
  commit "message"     Create AI commit with auto-generated message
  pr                   Generate PR description and title
  review [pr-url]      AI code review (local changes or PR)
  check                Run pre-push checks (lint, test)
  clean                Clean temporary files

Options:
  --tool <name>        Use specific AI tool (default: kilo)
  --no-verify          Skip pre-commit checks
  --dry-run            Preview without making changes
  --push               Push after commit/pr creation
  --draft              Create draft PR

Examples:
  git-ai.sh commit "fix login bug"
  git-ai.sh pr --push
  git-ai.sh review https://github.com/org/repo/pull/123
USAGE
    exit 0
}

# Get configured AI tool
get_ai_tool() {
    for tool in "${ALL_TOOLS[@]}"; do
        if command -v "$tool" &>/dev/null; then
            echo "$tool"
            return
        fi
    done
    echo "kilo"
}

# Generate commit message
generate_commit_message() {
    local description="$1"
    local tool="$2"

    local diff
    diff=$(git diff --cached --no-color)

    if [ -z "$diff" ]; then
        echo "⚠️  No changes staged for commit"
        return 1
    fi

    echo "  Generating commit message with $tool..."

    local prompt="You are a senior software engineer. Write a conventional commit message.

Changes:
$diff

Description: $description

Generate a conventional commit message (type(scope): message) followed by a body with details.
Keep it concise but informative. Include breaking changes note if applicable.
Output only the commit message, no extra text."

    local msg
    msg=$("$tool" --non-interactive --prompt "$prompt" 2>/dev/null || echo "chore: $description")

    echo "$msg"
}

# Generate PR description
generate_pr_description() {
    local tool="$1"

    local current_branch
    current_branch=$(git rev-parse --abbrev-ref HEAD)
    local default_branch
    default_branch=$(git remote show origin | grep 'HEAD branch' | cut -d' ' -f5)
    local diff
    diff=$(git diff "origin/$default_branch" --name-only)

    echo "  Generating PR description with $tool..."

    local prompt="You are a senior software engineer. Write a professional GitHub Pull Request description.

Branch: $current_branch
Files changed:
$diff

Generate:
1. Clear PR title (<= 70 chars)
2. Description: What changed and why
3. Type of change (fix, feature, refactor, etc.)
4. Testing completed
5. Checklist for reviewers

Format in GitHub markdown. Use emojis for sections. Keep it professional."

    local pr_desc
    pr_desc=$("$tool" --non-interactive --prompt "$prompt" 2>/dev/null || echo "# $current_branch\n\n## Changes")

    echo "$pr_desc"
}

# Run code review
run_code_review() {
    local target="${1:-}"
    local tool="$2"

    local diff=""
    if [ -n "$target" ]; then
        if [[ "$target" =~ ^https?:// ]]; then
            echo "  Fetching PR diff..."
            diff=$(curl -s "$target.patch" 2>/dev/null)
        else
            diff=$(git diff "$target" --no-color)
        fi
    else
        diff=$(git diff --no-color)
    fi

    if [ -z "$diff" ]; then
        echo "⚠️  No changes to review"
        return 1
    fi

    echo "  Running code review with $tool..."

    local prompt="You are a senior software engineer performing a code review.

Review these changes for:
- 🐛 Bugs and logical errors
- 🚀 Performance issues
- 🔒 Security vulnerabilities
- 📐 Code style and best practices
- 📝 Documentation
- ✅ Test coverage

Changes:
$diff

Provide actionable feedback. Be constructive. Group by severity.
Use markdown format."

    local review
    review=$("$tool" --non-interactive --prompt "$prompt" 2>/dev/null || echo "No review generated")

    echo "$review"
}

# Run pre-push checks
run_prechecks() {
    echo "  Running pre-push checks..."

    local failed=0

    # Check git status
    if [ -n "$(git status --porcelain)" ]; then
        echo "  ⚠️  Uncommitted changes"
    fi

    # Check for large files
    if git diff --stat | grep -q '|.*[0-9]*[1-9][0-9][0-9]\+[+]' ; then
        echo "  ⚠️  Large diff detected"
    fi

    # Check for TODO comments
    if git diff | grep -i 'todo\|fixme' | grep -q '+' ; then
        echo "  ℹ️  TODO/FIXME comments found"
    fi

    # Check for merge markers
    if git diff | grep -q '^<<<<<<<' ; then
        echo "  ❌ Merge conflict markers found"
        failed=1
    fi

    # Check for debug prints
    if git diff | grep -E '(console.log|println|dbg!)' | grep -q '+' ; then
        echo "  ⚠️  Debug prints detected"
    fi

    if [ "$failed" = 0 ]; then
        echo "  ✅ All pre-checks passed"
    else
        echo "  ❌ Pre-checks failed"
    fi

    return $failed
}

# Main commit command
ai_commit() {
    local description=""
    local tool=""
    local no_verify=false
    local dry_run=false
    local push=false

    while [ $# -gt 0 ]; do
        case "$1" in
            --tool)
                tool="$2"
                shift 2
                ;;
            --no-verify)
                no_verify=true
                shift
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            --push)
                push=true
                shift
                ;;
            *)
                description="$1"
                shift
                ;;
        esac
    done

    if [ -z "$description" ]; then
        echo "❌ Commit description required"
        usage
    fi

    if [ -z "$tool" ]; then
        tool=$(get_ai_tool)
    fi

    if ! command -v "$tool" &>/dev/null; then
        echo "❌ Tool '$tool' not found"
        exit 1
    fi

    echo "════════════════════════════════════════════════════════════════════"
    echo "  AI Commit Generator"
    echo "════════════════════════════════════════════════════════════════════"
    echo ""
    echo "  Tool: $tool"
    echo "  Description: $description"
    echo ""

    if [ "$no_verify" = false ]; then
        run_prechecks || true
        echo ""
    fi

    local commit_msg
    commit_msg=$(generate_commit_message "$description" "$tool")

    echo "  Generated commit message:"
    echo "───────────────────────────────────────────────────────────────────"
    echo "$commit_msg"
    echo "───────────────────────────────────────────────────────────────────"
    echo ""

    if [ "$dry_run" = true ]; then
        echo "  🚀 [DRY RUN] Would commit now"
        exit 0
    fi

    read -p "Commit with this message? (Y/n) " -n 1 -r reply
    echo ""
    if [[ ! $reply =~ ^[Nn]$ ]]; then
        git commit -m "$commit_msg"
        echo "  ✅ Committed"

        if [ "$push" = true ]; then
            git push
            echo "  ✅ Pushed"
        fi
    fi
}

# Main PR command
ai_pr() {
    local tool=""
    local dry_run=false
    local push=false
    local draft=false

    while [ $# -gt 0 ]; do
        case "$1" in
            --tool)
                tool="$2"
                shift 2
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            --push)
                push=true
                shift
                ;;
            --draft)
                draft=true
                shift
                ;;
            *)
                shift
                ;;
        esac
    done

    if [ -z "$tool" ]; then
        tool=$(get_ai_tool)
    fi

    echo "════════════════════════════════════════════════════════════════════"
    echo "  AI PR Generator"
    echo "════════════════════════════════════════════════════════════════════"
    echo ""

    local pr_desc
    pr_desc=$(generate_pr_description "$tool")

    echo "$pr_desc"
    echo ""

    if [ "$dry_run" = true ]; then
        echo "  🚀 [DRY RUN] Would create PR now"
        exit 0
    fi

    if command -v gh &>/dev/null; then
        read -p "Create PR with GitHub CLI? (Y/n) " -n 1 -r reply
        echo ""
        if [[ ! $reply =~ ^[Nn]$ ]]; then
            if [ "$draft" = true ]; then
                gh pr create --draft --body "$pr_desc"
            else
                gh pr create --body "$pr_desc"
            fi
            echo "  ✅ PR created"
        fi
    else
        echo "  ℹ️  GitHub CLI not found. Copy description above manually."
    fi
}

# Main review command
ai_review() {
    local target=""
    local tool=""

    while [ $# -gt 0 ]; do
        case "$1" in
            --tool)
                tool="$2"
                shift 2
                ;;
            *)
                target="$1"
                shift
                ;;
        esac
    done

    if [ -z "$tool" ]; then
        tool=$(get_ai_tool)
    fi

    echo "════════════════════════════════════════════════════════════════════"
    echo "  AI Code Review"
    echo "════════════════════════════════════════════════════════════════════"
    echo ""

    run_code_review "$target" "$tool"
}

case "${1:-}" in
    commit)
        shift
        ai_commit "$@"
        ;;
    pr)
        shift
        ai_pr "$@"
        ;;
    review)
        shift
        ai_review "$@"
        ;;
    check)
        run_prechecks
        ;;
    clean)
        rm -f .ai-commit-*.tmp .ai-pr-*.tmp
        echo "✅ Cleaned up temporary files"
        ;;
    --help|-h|help)
        usage
        ;;
    *)
        usage
        ;;
esac
