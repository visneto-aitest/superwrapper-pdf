# Scripts Improvements - Review Findings & Recommendations

**Date:** April 10, 2026  
**Scope:** All bash scripts in `/scripts/` directory  
**Total Scripts Reviewed:** 39 files (~6,400+ lines)

---

## Executive Summary

The scripts are production-ready overall, with solid architecture and good security patterns (credential masking, `chmod 600`, safe JSON validation). However, several critical bugs, security improvements, and efficiency gains are identified.

**Priority Breakdown:**
- 🔴 **Critical:** 4 issues (fix immediately)
- 🟡 **High:** 8 issues (fix before next release)
- 🟢 **Medium:** 7 suggestions (improvements for future)
- 🔵 **Low:** 5 nice-to-haves (polish)

---

## 🔴 Critical Issues

### ✅ C1: `codex-profile.sh` Python `sys` Import Missing - **FIXED**

**File:** `codex-profile.sh:77-91`  
**Status:** ✅ Resolved - Added `import sys` and changed `open('$file')` to `open(sys.argv[1])` with `"$file"` passed as argument.

---

### ✅ C2: `cost-analyzer.sh` Undefined Variables in `show_forecast` - **FIXED**

**File:** `cost-analyzer.sh:311`  
**Status:** ✅ Resolved - Changed `$total_cost` to `$total_daily` and `$threshold` to `$THRESHOLD_DAILY` to match the variables defined in the function.

---

### ✅ C3: `ai-orchestrator.sh` Best Result Selection Always Picks First - **FIXED**

**File:** `ai-orchestrator.sh:195-218`  
**Status:** ✅ Resolved - Modified Python scoring to output `BEST:<tool>` marker, which bash then extracts and uses. Falls back to first tool only if parsing fails.

---

### ✅ C4: Python Code Injection via File Path Interpolation - **FIXED**

**Status:** ✅ **All 28 occurrences fixed across 11 scripts**

**Fixed scripts:**
- ✅ **All `*-profile.sh` scripts** (8 occurrences): claude, codex, opencode, qwen
- ✅ **All `*-status.sh` scripts** (14 occurrences): claude, codex (4), qwen (4), opencode (2), gemini (3)
- ✅ **Other scripts** (6 occurrences): ai-orchestrator.sh (1), qwen-env.sh (2), gemini-profile.sh (1), claude-status.sh (1)

**Fix pattern applied consistently:**
```bash
# Before (vulnerable):
python3 -c "import json; data = json.load(open('$CODEX_AUTH')); ..." 2>/dev/null

# After (safe):
python3 -c "import json, sys; data = json.load(open(sys.argv[1])); ..." "$CODEX_AUTH" 2>/dev/null
```

**Impact eliminated:** File paths with special characters (quotes, backticks, $VAR) can no longer inject arbitrary Python code.

---

## 🟡 High Priority Issues

### H1: Inconsistent `_validate_env_file` Implementations

**Files:** All `*-env.sh` scripts vs `lib/common.sh`  
**Issue:** Three different implementations exist:
1. `lib/common.sh`: Returns `0`/`1`
2. Inline versions: `return $errors` (can exit > 125, wrapping exit codes)
3. Minified fallbacks: Single-line versions

Scripts that don't source `lib/common.sh` (`claude-env.sh`, `codex-env.sh`, `opencode-env.sh`) should be refactored to use the library.

**Fix:** All scripts should source `lib/common.sh` and use the single implementation.

---

### H2: API Key Visibility in Process List

**Files:** All `*-status.sh` scripts, `ai-health.sh`  
**Issue:** When `curl` is invoked with `-H "x-api-key: $ANTHROPIC_API_KEY"`, the key is visible to other users via `ps aux`.

**Fix:** Use `curl --config` with the key in a temporary file:

```bash
local tmpfile
tmpfile=$(mktemp)
echo "header = \"x-api-key: $ANTHROPIC_API_KEY\"" > "$tmpfile"
chmod 600 "$tmpfile"
curl -s --config "$tmpfile" ...
rm -f "$tmpfile"
```

---

### H3: Missing Connection Timeouts on All `curl` Calls

**Files:** All `*-status.sh` scripts, `ai-health.sh`  
**Issue:** `curl` calls don't use `--connect-timeout` or `--max-time`, meaning slow/hijacked connections could hang indefinitely.

**Fix:** Add timeouts to all curl calls:

```bash
curl -s --connect-timeout 10 --max-time 30 ...
```

---

### H4: `source` of User-Editable `.env` Files Without Validation

**Files:** All `*-env.sh` scripts (`load_account` and `run_with_account`)  
**Issue:** If an attacker can write to the accounts directory, they can execute arbitrary commands through crafted `.env` files. No validation that the directory has restrictive permissions.

**Fix:**
```bash
# Before sourcing, check directory permissions
local dir_perms
dir_perms=$(stat -f '%A' "$CODEX_ACCOUNTS_DIR" 2>/dev/null || stat -c '%a' "$CODEX_ACCOUNTS_DIR" 2>/dev/null)
if [ "${dir_perms}" != "600" ] && [ "${dir_perms}" != "700" ]; then
    echo "❌ Error: Accounts directory has unsafe permissions: $dir_perms"
    exit 1
fi
```

---

### H5: `return $errors` Can Exit with Invalid Codes

**Files:** `claude-env.sh:~82`, `codex-env.sh:~64`, `opencode-env.sh:~83`  
**Issue:** `return $errors` where `errors > 125` causes exit code wrapping. Should return `0` or `1` only.

**Fix:**
```bash
if [ "$errors" -gt 0 ]; then
    return 1
fi
return 0
```

---

### H6: Unquoted Variable Assignments

**Files:** Throughout all scripts  
**Issue:** `local file=$1` instead of `local file="$1"` violates best practices and is fragile.

**Locations:**
- `claude-env.sh:~79`, `~85`, `~100`
- `codex-env.sh:~61`, `~67`
- `opencode-env.sh:~80`, `~86`
- `qwen-env.sh:~113`, `~119`

**Fix:** Quote all variable assignments.

---

### H7: `shopt -s nullglob` Without Guaranteed Restore

**Files:** `claude-env.sh`, `codex-env.sh`, `kilo-env.sh`, `opencode-env.sh`, `gemini-env.sh`  
**Issue:** If script exits between `set` and `unset` (due to `set -e`), nullglob state is corrupted.

**Fix:** Use subshell or trap:

```bash
(
    shopt -s nullglob
    for f in "$DIR"/*.env; do
        # ... process
    done
)
```

---

### H8: `_grep_env_key` Regex Metacharacters Not Escaped

**Files:** `lib/common.sh:~117`, all `*-env.sh` scripts  
**Issue:** `$key` is not escaped for regex in `grep -E "^${key}="`. While env var names rarely contain metacharacters, this is fragile.

**Fix:** Either use `grep -F` or escape the key:

```bash
local escaped_key
escaped_key=$(printf '%s' "$key" | sed 's/[][\\.^$*+?(){}|/]/\\&/g')
result=$(grep -E "^${escaped_key}=" "$file" 2>/dev/null | head -1 | cut -d'=' -f2-) || result=""
```

---

## 🟢 Medium Priority Suggestions

### M1: Consolidate `*-env.sh` Duplication

**Issue:** 4 of 6 env scripts duplicate 200+ lines of identical code (`_hash_string`, `_get_editor`, `_mask_value`, `_validate_env_file`, `list_accounts`, `create_account`, etc.). Only provider variable arrays and usage text differ.

**Recommendation:** Parameterize from a single template in `lib/common.sh`:

```bash
# Generic account manager factory
_create_account_manager() {
    local tool_name="$1"
    local accounts_dir="$2"
    local provider_vars=("${!3}")
    local secret_vars=("${!4}")
    # Generate all functions dynamically
}
```

Or use a configuration-driven approach:
```bash
# Account config file
TOOL_NAME="claude"
ACCOUNTS_DIR="$HOME/.config/claude/accounts"
PROVIDER_VARS=(ANTHROPIC_API_KEY AWS_ACCESS_KEY_ID ...)
SECRET_VARS=(ANTHROPIC_API_KEY AWS_ACCESS_KEY_ID ...)
source lib/account-manager.sh
```

**Impact:** Reduce ~3,000 lines of duplication to ~500 lines of shared code.

---

### M2: Create Python Utility Module

**Issue:** Python one-liners scattered throughout scripts for JSON/TOML parsing, auth.json reading, etc.

**Recommendation:** Create `lib/utils.py` with a CLI interface:

```python
#!/usr/bin/env python3
"""Shared utilities for AI CLI scripts."""

import json
import sys
import toml

def validate_json(path):
    try:
        with open(path) as f:
            json.load(f)
        return True
    except (json.JSONDecodeError, FileNotFoundError):
        return False

def get_oauth_token(path, tool):
    """Extract OAuth token from auth file."""
    with open(path) as f:
        data = json.load(f)
    # Tool-specific extraction logic
    ...

if __name__ == "__main__":
    command = sys.argv[1]
    if command == "validate-json":
        sys.exit(0 if validate_json(sys.argv[2]) else 1)
    elif command == "get-oauth-token":
        print(get_oauth_token(sys.argv[2], sys.argv[3]))
    # ... more commands
```

Then bash scripts call: `python3 lib/utils.py validate-json "$file"`

---

### M3: Reduce Excessive `grep` Pipelines in `list_accounts`

**Issue:** Each account file is grepped 5-10 times sequentially. For N accounts × M variables, this is O(N×M) file reads.

**Recommendation:** Parse each file once:

```bash
# Parse all vars from file in one pass
parse_env_file() {
    local file="$1"
    while IFS='=' read -r key value; do
        case "$key" in
            ANTHROPIC_API_KEY) echo "anthropic=$value" ;;
            OPENAI_API_KEY) echo "openai=$value" ;;
            # ... etc
        esac
    done < <(grep -E '^[A-Z_]+=' "$file" 2>/dev/null || true)
}
```

Or use Python for bulk parsing:
```bash
python3 -c "
import sys
with open(sys.argv[1]) as f:
    for line in f:
        if '=' in line and not line.startswith('#'):
            k, v = line.strip().split('=', 1)
            print(f'{k}={v}')
" "$file"
```

---

### M4: Add `--dry-run` Consistency Across All Scripts

**Issue:** Some scripts support `DRY_RUN=1` (via `_dry_run` helper), others don't. Not all productivity scripts respect this flag.

**Recommendation:** Ensure all scripts that modify state (create, delete, switch) support `DRY_RUN=1`.

---

### M5: Standardize Error Messages and Exit Codes

**Issue:** Inconsistent error message formats:
- Some use `❌ Error:`, others use `Error:`
- Some use emojis (✅, ❌, ⚠), others don't
- Exit codes vary: some use `exit 1`, others `exit 2`

**Recommendation:** Define constants in `lib/common.sh`:

```bash
# Standard error formatting
_err() { printf '❌ Error: %s\n' "$1" >&2; }
_warn() { printf '⚠ Warning: %s\n' "$1" >&2; }
_info() { printf '✅ %s\n' "$1"; }
_success() { printf '✅ %s\n' "$1"; }

# Standard exit codes
EXIT_SUCCESS=0
EXIT_USAGE=1
EXIT_NOT_FOUND=2
EXIT_PERMISSION=3
EXIT_RUNTIME=4
```

---

### M6: Add Input Validation for File Paths

**Issue:** Functions that accept file paths don't validate them. A path like `/` or `""` could cause unexpected behavior.

**Recommendation:** Add path validation helper:

```bash
_validate_path() {
    local path="$1"
    local type="${2:-file}"  # file, dir, any
    
    if [ -z "$path" ]; then
        _err "Empty path provided"
        return 1
    fi
    
    # Prevent path traversal
    local resolved
    resolved=$(realpath -m "$path" 2>/dev/null || echo "$path")
    if [[ "$resolved" == /* ]]; then
        # Check it's not a system path
        case "$resolved" in
            /|/etc|/usr|/var|/System)
                _err "Refusing to operate on system path: $resolved"
                return 1
                ;;
        esac
    fi
    
    case "$type" in
        file) [ -f "$path" ] || { _err "Not a file: $path"; return 1; } ;;
        dir)  [ -d "$path" ] || { _err "Not a directory: $path"; return 1; } ;;
    esac
    return 0
}
```

---

### M7: Add Health Check Integration to All Status Scripts

**Issue:** `*-status.sh` scripts check their own tool status, but `ai-health.sh` duplicates this logic.

**Recommendation:** Have `ai-health.sh` delegate to individual status scripts with a standardized `--health-check` flag:

```bash
# In ai-health.sh
check_tool_status() {
    local tool="$1"
    local script="${tool}-status.sh"
    
    if [ -x "$script" ]; then
        "$script" --health-check --json
    else
        echo "{\"tool\":\"$tool\",\"status\":\"unknown\",\"error\":\"no status script\"}"
    fi
}
```

---

## 🔵 Low Priority / Nice to Have

### L1: Add `read` Timeouts for Non-Interactive Contexts

**Files:** All `delete_profile` functions, `ai-orchestrator.sh`, `git-ai.sh`  
**Issue:** `read -p` hangs forever in CI/cron contexts.

**Fix:**
```bash
# Add timeout and check if interactive
if [ -t 0 ]; then
    read -r -p "Confirm? [y/N] " confirm
else
    echo "❌ Non-interactive mode: cannot prompt. Use --force."
    exit 1
fi
```

---

### L2: Add ShellCheck Annotations

Run [ShellCheck](https://www.shellcheck.net/) across all scripts and fix warnings:

```bash
# Install
brew install shellcheck

# Run
shellcheck scripts/*.sh scripts/lib/*.sh

# Fix common warnings
# SC2086: Double quote to prevent globbing
# SC2154: Variable referenced but not assigned
# SC2002: Useless use of cat
```

---

### L3: Add Bash Completion

Generate completion scripts for all env/profile/status scripts:

```bash
# scripts/completions/claude-env.bash
_claude_env_completions() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    local commands="list create show edit validate"
    # Add account names from directory
    local accounts
    accounts=$(ls ~/.config/claude/accounts/*.env 2>/dev/null | xargs -I{} basename {} .env)
    COMPREPLY=($(compgen -W "$commands $accounts" -- "$cur"))
}
complete -F _claude_env_completions claude-env.sh
```

---

### L4: Add Metrics Collection

Track usage patterns to identify bottlenecks:

```bash
# In lib/common.sh
_log_usage() {
    local script="$1"
    local action="$2"
    local duration="${3:-0}"
    
    local log_file="${SCRIPT_USAGE_LOG:-/tmp/ai-cli-usage.log}"
    printf '%s\t%s\t%s\t%s\n' "$(date +%s)" "$script" "$action" "$duration" >> "$log_file"
}
```

---

### L5: Portability Improvements

**Issue:** Some commands are macOS-specific (`stat -f`, `shasum`) or Linux-specific (`stat -c`, `sha256sum`).

**Fix:** Already partially handled with fallbacks, but some gaps remain:
- `date` format differences between platforms
- `find` options vary
- `sed` regex syntax differs

Consider using a compatibility layer or documenting platform requirements.

---

## Implementation Roadmap

### Phase 1: Critical Fixes - **ALL COMPLETE** ✅
- [x] Fix `codex-profile.sh` Python `sys` import bug (C1) ✅
- [x] Fix `cost-analyzer.sh` undefined variables (C2) ✅
- [x] Fix `ai-orchestrator.sh` result selection (C3) ✅
- [x] Fix Python injection in `*-profile.sh` scripts (C4a) ✅
- [x] Fix Python injection in `*-status.sh` and other scripts (C4b) ✅

### Phase 2: Security & Reliability (This Week)
- [ ] Unify `_validate_env_file` implementations (H1)
- [ ] Add connection timeouts to all `curl` calls (H3)
- [ ] Add directory permission validation before `source` (H4)
- [ ] Fix `return $errors` exit codes (H5)
- [ ] Quote all variable assignments (H6)
- [ ] Fix `nullglob` scope issues (H7)

### Phase 3: Code Quality (Next Sprint)
- [ ] Consolidate `*-env.sh` duplication (M1)
- [ ] Create Python utility module (M2)
- [ ] Reduce grep pipeline redundancy (M3)
- [ ] Standardize error messages (M5)

### Phase 4: Polish (Future)
- [ ] Run ShellCheck and fix all warnings (L2)
- [ ] Add bash completions (L3)
- [ ] Add metrics collection (L4)
- [ ] Improve platform portability (L5)

---

## Overall Assessment

**Code Quality Score: B+ (85/100)**

The scripts demonstrate strong engineering with good security practices, clean architecture, and useful productivity features. The main areas for improvement are:
1. Code reuse across similar scripts
2. Edge case handling in Python subprocess calls
3. Standardization of patterns across tools

The OAuth token support recently added significantly improves CI/CD and headless server capabilities, which is a major enhancement.

**Recommendation:** Address Phase 1 critical bugs immediately, then work through Phases 2-3 systematically. Phase 4 items can be prioritized based on user feedback.
