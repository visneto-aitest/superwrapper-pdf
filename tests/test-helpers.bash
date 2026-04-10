#!/usr/bin/env bash
# test-helpers.bash - Shared test helpers for all CLI tool tests
#
# Usage: source this from .bats files
#
# Provides:
#   _setup_tool_env <tool>          Set up temp dirs and script path
#   _teardown_tool                 Clean up temp directories
#   _run_script <tool> <args...>    Run a tool script with isolated env
#   _assert_exit_code <expected>    Assert last command exit code
#   _assert_output_contains <str>   Assert stdout contains string
#   _assert_file_exists <path>      Assert file exists
#   _assert_file_not_exists <path>  Assert file does not exist

SCRIPTS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts"

# Tool configuration map
declare -A TOOL_ENV_SCRIPT=(
    [kilo]="kilo-env.sh"
    [opencode]="opencode-env.sh"
    [claude]="claude/claude-env.sh"
    [qwen]="qwen/qwen-env.sh"
    [gemini]="gemini-env.sh"
)

declare -A TOOL_PROFILE_SCRIPT=(
    [kilo]="kilo-profile.sh"
    [opencode]="opencode-profile.sh"
    [claude]="claude/claude-profile.sh"
    [qwen]="qwen/qwen-profile.sh"
    [gemini]="gemini-profile.sh"
)

declare -A TOOL_STATUS_SCRIPT=(
    [kilo]="kilo-status.sh"
    [opencode]="opencode-status.sh"
    [claude]="claude-status.sh"
    [qwen]="qwen-status.sh"
    [gemini]="gemini-status.sh"
)

declare -A TOOL_ACCOUNTS_DIR_ENV=(
    [kilo]="KILO_ACCOUNTS_DIR"
    [opencode]="OPENCODE_ACCOUNTS_DIR"
    [claude]="CLAUDE_ACCOUNTS_DIR"
    [qwen]="QWEN_ACCOUNTS_DIR"
    [gemini]="GEMINI_ACCOUNTS_DIR"
)

declare -A TOOL_CONFIG_DIR_ENV=(
    [kilo]="KILO_CONFIG_DIR"
    [opencode]="OPENCODE_CONFIG_DIR"
    [claude]="CLAUDE_CONFIG_DIR"
    [qwen]="QWEN_CONFIG_DIR"
    [gemini]="GEMINI_CONFIG_DIR"
)

declare -A TOOL_DEFAULT_PROVIDER_VARS=(
    [kilo]="ANTHROPIC_API_KEY"
    [opencode]="ANTHROPIC_API_KEY"
    [claude]="ANTHROPIC_API_KEY"
    [qwen]="OPENAI_API_KEY"
    [gemini]="GEMINI_API_KEY"
)

# ─── Setup / Teardown ────────────────────────────────────────────────────────

_setup_tool_env() {
    local tool="$1"
    TEST_TEMP=$(mktemp -d)

    # Create isolated directories
    mkdir -p "$TEST_TEMP/accounts"
    mkdir -p "$TEST_TEMP/config"
    mkdir -p "$TEST_TEMP/sessions"
    mkdir -p "$TEST_TEMP/logs"
    mkdir -p "$TEST_TEMP/auth"

    # Create valid test config
    cat > "$TEST_TEMP/config/opencode.json" << 'TESTCFG'
{
  "model": "anthropic/claude-sonnet-4-20250514",
  "provider": {
    "anthropic": {
      "options": {
        "apiKey": "{env:ANTHROPIC_API_KEY}"
      }
    },
    "openai": {
      "options": {
        "apiKey": "{env:OPENAI_API_KEY}"
      }
    }
  }
}
TESTCFG

    # Create test account
    cat > "$TEST_TEMP/accounts/test.env" << 'TESTACCT'
ANTHROPIC_API_KEY=sk-test-fake-key-12345678
OPENAI_API_KEY=sk-proj-fake-key-12345678
TESTACCT

    # Create test account with all providers
    cat > "$TEST_TEMP/accounts/full.env" << 'TESTACCT'
ANTHROPIC_API_KEY=sk-ant-full-key-abcdef123456
OPENAI_API_KEY=sk-proj-full-key-abcdef123456
GEMINI_API_KEY=ai-full-key-abcdef123456
TESTACCT

    # Create invalid config
    cat > "$TEST_TEMP/config-invalid.json" << 'TESTINV'
{invalid json, missing quotes: true,
TESTINV

    # Create valid JSON for validation tests
    cat > "$TEST_TEMP/config-valid.json" << 'TESTVAL'
{"key": "value", "nested": {"a": 1}}
TESTVAL
}

_teardown_tool() {
    if [ -n "${TEST_TEMP:-}" ] && [ -d "${TEST_TEMP:-}" ]; then
        rm -rf "$TEST_TEMP"
    fi
    unset TEST_TEMP
}

# ─── Run Script ──────────────────────────────────────────────────────────────

_run_script() {
    local tool="$1"
    local script_type="$2"  # env, profile, status
    shift 2

    local script_path=""
    local env_vars=""

    case "$script_type" in
        env)
            script_path="${SCRIPTS_ROOT}/${TOOL_ENV_SCRIPT[$tool]}"
            env_vars="${TOOL_ACCOUNTS_DIR_ENV[$tool]}=$TEST_TEMP/accounts"
            ;;
        profile)
            script_path="${SCRIPTS_ROOT}/${TOOL_PROFILE_SCRIPT[$tool]}"
            env_vars="${TOOL_CONFIG_DIR_ENV[$tool]}=$TEST_TEMP/config ${TOOL_ACCOUNTS_DIR_ENV[$tool]}=$TEST_TEMP/accounts"
            ;;
        status)
            script_path="${SCRIPTS_ROOT}/${TOOL_STATUS_SCRIPT[$tool]}"
            env_vars="${TOOL_ACCOUNTS_DIR_ENV[$tool]}=$TEST_TEMP/accounts ${TOOL_CONFIG_DIR_ENV[$tool]}=$TEST_TEMP/config"
            ;;
    esac

    # Run with isolated environment
    HOME="$TEST_TEMP" \
    PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
    $env_vars \
        bash "$script_path" "$@" 2>&1
}

_run_script_raw() {
    local script_path="$1"
    shift
    bash "$script_path" "$@" 2>&1
}

# ─── Assertions ──────────────────────────────────────────────────────────────

_assert_exit_code() {
    local expected="$1"
    local actual="${BASH_REMATCH[0]:-$?}"
    # bats captures exit code in $status
    [ "${status:-99}" -eq "$expected" ] || {
        echo "Expected exit code $expected, got ${status:-99}"
        return 1
    }
}

_assert_output_contains() {
    local expected="$1"
    [[ "${output:-}" == *"$expected"* ]] || {
        echo "Output does not contain '$expected'"
        echo "Got: $output"
        return 1
    }
}

_assert_output_not_contains() {
    local unexpected="$1"
    [[ "${output:-}" != *"$unexpected"* ]] || {
        echo "Output should not contain '$unexpected'"
        echo "Got: $output"
        return 1
    }
}

_assert_output_matches_regex() {
    local pattern="$1"
    [[ "${output:-}" =~ $pattern ]] || {
        echo "Output does not match regex '$pattern'"
        echo "Got: $output"
        return 1
    }
}

_assert_file_exists() {
    [ -f "$1" ] || {
        echo "File does not exist: $1"
        return 1
    }
}

_assert_file_not_exists() {
    [ ! -f "$1" ] || {
        echo "File should not exist: $1"
        return 1
    }
}

_assert_dir_exists() {
    [ -d "$1" ] || {
        echo "Directory does not exist: $1"
        return 1
    }
}

# ─── Test Data Creators ──────────────────────────────────────────────────────

_create_account() {
    local name="$1"
    local content="${2:-ANTHROPIC_API_KEY=sk-test-$name-key-12345}"
    echo "$content" > "$TEST_TEMP/accounts/$name.env"
    chmod 600 "$TEST_TEMP/accounts/$name.env"
}

_create_valid_config() {
    cat > "$TEST_TEMP/config/opencode.json" << 'EOF'
{
  "model": "anthropic/claude-sonnet-4-20250514",
  "provider": {
    "anthropic": {
      "options": { "apiKey": "{env:ANTHROPIC_API_KEY}" }
    }
  }
}
EOF
}

_create_invalid_config() {
    echo "{invalid json" > "$TEST_TEMP/config/opencode.json"
}

_create_profile_dir() {
    local name="$1"
    mkdir -p "$TEST_TEMP/config/profiles/$name"
    cat > "$TEST_TEMP/config/profiles/$name/opencode.json" << 'EOF'
{
  "model": "anthropic/claude-sonnet-4-20250514",
  "provider": {
    "anthropic": {
      "options": { "apiKey": "{env:ANTHROPIC_API_KEY}" }
    }
  }
}
EOF
}
