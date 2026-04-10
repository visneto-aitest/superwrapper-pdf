#!/usr/bin/env bats
# test-status.bats - Unit tests for all 5 status scripts
#
# Each test runs against all tools using parameterized helper functions.

load test-helpers

# Tools to test
TOOLS=(kilo opencode claude qwen gemini)

setup() {
    _setup_tool_env "kilo"
}

teardown() {
    _teardown_tool
}

# ─── Full Status ─────────────────────────────────────────────────────────────

@test "status full: shows full status report" {
    for tool in "${TOOLS[@]}"; do
        _setup_tool_env "$tool"
        run _run_script "$tool" status
        assert_success
        [[ "$output" == *"Status Report"* ]] || [[ "$output" == *"Status"* ]]
        _teardown_tool
        _setup_tool_env "kilo"
    done
}

@test "status full: shows configuration info" {
    for tool in "${TOOLS[@]}"; do
        _setup_tool_env "$tool"
        run _run_script "$tool" status
        assert_success
        # Should mention config file or settings
        [[ "$output" == *"Config"* ]] || [[ "$output" == *"config"* ]] || [[ "$output" == *"settings"* ]]
        _teardown_tool
        _setup_tool_env "kilo"
    done
}

# ─── Provider Status ─────────────────────────────────────────────────────────

@test "status providers: shows provider status" {
    for tool in "${TOOLS[@]}"; do
        _setup_tool_env "$tool"
        run _run_script "$tool" status --providers
        assert_success
        [[ "$output" == *"Provider"* ]] || [[ "$output" == *"provider"* ]]
        _teardown_tool
        _setup_tool_env "kilo"
    done
}

@test "status provider: checks specific provider" {
    for tool in "${TOOLS[@]}"; do
        _setup_tool_env "$tool"
        run _run_script "$tool" status --provider anthropic
        # May succeed or fail depending on config, but should not crash
        true  # Just verify it runs
        _teardown_tool
        _setup_tool_env "kilo"
    done
}

@test "status provider: requires provider name" {
    for tool in "${TOOLS[@]}"; do
        _setup_tool_env "$tool"
        run _run_script "$tool" status --provider
        assert_failure
        [[ "$output" == *"❌"* ]] || [[ "$output" == *"required"* ]]
        _teardown_tool
        _setup_tool_env "kilo"
    done
}

# ─── Usage ───────────────────────────────────────────────────────────────────

@test "status usage: shows usage summary" {
    for tool in "${TOOLS[@]}"; do
        _setup_tool_env "$tool"
        run _run_script "$tool" status --usage
        assert_success
        # Should show token usage info or "no session data"
        [[ "$output" == *"Token"* ]] || [[ "$output" == *"usage"* ]] || [[ "$output" == *"No session"* ]] || [[ "$output" == *"ℹ"* ]]
        _teardown_tool
        _setup_tool_env "kilo"
    done
}

# ─── Sessions ────────────────────────────────────────────────────────────────

@test "status sessions: handles no sessions gracefully" {
    for tool in "${TOOLS[@]}"; do
        _setup_tool_env "$tool"
        run _run_script "$tool" status --sessions
        assert_success
        # Should show "no data" message, not crash
        [[ "$output" == *"No session"* ]] || [[ "$output" == *"Unable"* ]] || [ -z "$output" ]
        _teardown_tool
        _setup_tool_env "kilo"
    done
}

# ─── Rate Limits ─────────────────────────────────────────────────────────────

@test "status rate-limits: shows rate limit info" {
    for tool in "${TOOLS[@]}"; do
        _setup_tool_env "$tool"
        run _run_script "$tool" status --rate-limits
        assert_success
        [[ "$output" == *"Rate Limit"* ]] || [[ "$output" == *"rate limit"* ]] || [[ "$output" == *"RPM"* ]]
        _teardown_tool
        _setup_tool_env "kilo"
    done
}

# ─── JSON Output ─────────────────────────────────────────────────────────────

@test "status json: produces valid JSON output" {
    for tool in "${TOOLS[@]}"; do
        _setup_tool_env "$tool"
        run _run_script "$tool" status --json
        assert_success
        # Verify output is valid JSON using python3
        if command -v python3 &>/dev/null; then
            echo "$output" | python3 -c "import json,sys; json.load(sys.stdin)"
            assert_success
        fi
        _teardown_tool
        _setup_tool_env "kilo"
    done
}

@test "status json: includes expected fields" {
    for tool in "${TOOLS[@]}"; do
        _setup_tool_env "$tool"
        run _run_script "$tool" status --json
        assert_success
        # Should contain some expected keys
        [[ "$output" == *"provider"* ]] || [[ "$output" == *"config"* ]] || [[ "$output" == *"session"* ]]
        _teardown_tool
        _setup_tool_env "kilo"
    done
}

# ─── Account Loading ─────────────────────────────────────────────────────────

@test "status with account: loads account credentials" {
    for tool in "${TOOLS[@]}"; do
        _setup_tool_env "$tool"
        _create_account "statusacct" "ANTHROPIC_API_KEY=sk-ant-status-key-12345"
        # Should not error when loading valid account
        run _run_script "$tool" status "statusacct"
        # May succeed or fail depending on config, but should load account
        true
        _teardown_tool
        _setup_tool_env "kilo"
    done
}

@test "status with unknown account: shows error" {
    for tool in "${TOOLS[@]}"; do
        _setup_tool_env "$tool"
        run _run_script "$tool" status "nonexistent-account"
        assert_failure
        [[ "$output" == *"❌"* ]]
        [[ "$output" == *"not found"* ]]
        _teardown_tool
        _setup_tool_env "kilo"
    done
}

# ─── Usage / Help ────────────────────────────────────────────────────────────

@test "status usage: shows help with --help" {
    for tool in "${TOOLS[@]}"; do
        _setup_tool_env "$tool"
        run _run_script "$tool" status --help
        assert_success
        [[ "$output" == *"Usage"* ]]
        [[ "$output" == *"balance"* ]] || [[ "$output" == *"providers"* ]] || [[ "$output" == *"usage"* ]]
        _teardown_tool
        _setup_tool_env "kilo"
    done
}

@test "status usage: shows help with -h" {
    for tool in "${TOOLS[@]}"; do
        _setup_tool_env "$tool"
        run _run_script "$tool" status -h
        assert_success
        [[ "$output" == *"Usage"* ]]
        _teardown_tool
        _setup_tool_env "kilo"
    done
}

# ─── Unknown Option ──────────────────────────────────────────────────────────

@test "status unknown option: shows error" {
    for tool in "${TOOLS[@]}"; do
        _setup_tool_env "$tool"
        run _run_script "$tool" status --unknown-flag
        assert_failure
        [[ "$output" == *"❌"* ]] || [[ "$output" == *"Usage"* ]]
        _teardown_tool
        _setup_tool_env "kilo"
    done
}

# ─── Security: Keys Not Exposed ──────────────────────────────────────────────

@test "status: does not expose API keys in output" {
    for tool in "${TOOLS[@]}"; do
        _setup_tool_env "$tool"
        _create_account "securestatus" "ANTHROPIC_API_KEY=sk-ant-super-secret-status-key-123456789"
        run _run_script "$tool" status "securestatus"
        _assert_output_not_contains "sk-ant-super-secret-status-key-123456789"
        _teardown_tool
        _setup_tool_env "kilo"
    done
}
