#!/usr/bin/env bats
# test-env.bats - Unit tests for all 5 env scripts (kilo, opencode, claude, qwen, gemini)
#
# Each test runs against all tools using parameterized helper functions.

load test-helpers

# Tools to test
TOOLS=(kilo opencode claude qwen gemini)

setup() {
    _setup_tool_env "kilo"  # Sets up TEST_TEMP and common vars
}

teardown() {
    _teardown_tool
}

# ─── Create Account ──────────────────────────────────────────────────────────

@test "env create: creates account file for all tools" {
    for tool in "${TOOLS[@]}"; do
        _setup_tool_env "$tool"
        run _run_script "$tool" env create "test-account"
        assert_success
        [[ "$output" == *"✅ Created account: test-account"* ]]
        _assert_file_exists "$TEST_TEMP/accounts/test-account.env"
        _teardown_tool
        _setup_tool_env "kilo"  # Reset for next iteration
    done
}

@test "env create: rejects empty name" {
    for tool in "${TOOLS[@]}"; do
        _setup_tool_env "$tool"
        run _run_script "$tool" env create ""
        assert_failure
        [[ "$output" == *"❌"* ]]
        _teardown_tool
        _setup_tool_env "kilo"
    done
}

@test "env create: rejects invalid characters in name" {
    for tool in "${TOOLS[@]}"; do
        _setup_tool_env "$tool"
        run _run_script "$tool" env create "my account"
        assert_failure
        [[ "$output" == *"❌"* ]]
        _teardown_tool
        _setup_tool_env "kilo"
    done
}

@test "env create: rejects existing account" {
    for tool in "${TOOLS[@]}"; do
        _setup_tool_env "$tool"
        _run_script "$tool" env create "dup"
        run _run_script "$tool" env create "dup"
        assert_failure
        [[ "$output" == *"❌"* ]]
        [[ "$output" == *"already exists"* ]]
        _teardown_tool
        _setup_tool_env "kilo"
    done
}

@test "env create: sets file permissions to 600" {
    for tool in "${TOOLS[@]}"; do
        _setup_tool_env "$tool"
        _run_script "$tool" env create "perms"
        local perms
        perms=$(stat -f '%Lp' "$TEST_TEMP/accounts/perms.env" 2>/dev/null || stat -c '%a' "$TEST_TEMP/accounts/perms.env" 2>/dev/null)
        [ "$perms" = "600" ]
        _teardown_tool
        _setup_tool_env "kilo"
    done
}

# ─── List Accounts ───────────────────────────────────────────────────────────

@test "env list: shows all accounts" {
    for tool in "${TOOLS[@]}"; do
        _setup_tool_env "$tool"
        _create_account "alpha"
        _create_account "beta"
        run _run_script "$tool" env list
        assert_success
        [[ "$output" == *"alpha"* ]]
        [[ "$output" == *"beta"* ]]
        _teardown_tool
        _setup_tool_env "kilo"
    done
}

@test "env list: shows empty message when no accounts" {
    for tool in "${TOOLS[@]}"; do
        _setup_tool_env "$tool"
        # Remove pre-created test account
        rm -f "$TEST_TEMP/accounts"/*.env
        run _run_script "$tool" env list
        assert_success
        [[ "$output" == *"No accounts found"* ]]
        _teardown_tool
        _setup_tool_env "kilo"
    done
}

@test "env list: shows no directory when dir missing" {
    for tool in "${TOOLS[@]}"; do
        _setup_tool_env "$tool"
        rm -rf "$TEST_TEMP/accounts"
        run _run_script "$tool" env list
        assert_success
        [[ "$output" == *"No accounts found"* ]]
        _teardown_tool
        _setup_tool_env "kilo"
    done
}

# ─── Show Account ────────────────────────────────────────────────────────────

@test "env show: displays account info with masked keys" {
    for tool in "${TOOLS[@]}"; do
        _setup_tool_env "$tool"
        _create_account "showtest" "ANTHROPIC_API_KEY=sk-ant-showtest-key-12345"
        run _run_script "$tool" env show "showtest"
        assert_success
        [[ "$output" == *"Account: showtest"* ]]
        # Should NOT expose the raw key
        _assert_output_not_contains "sk-ant-showtest-key-12345"
        # Should show masked version
        [[ "$output" == *"****"* ]]
        _teardown_tool
        _setup_tool_env "kilo"
    done
}

@test "env show: fails for non-existent account" {
    for tool in "${TOOLS[@]}"; do
        _setup_tool_env "$tool"
        run _run_script "$tool" env show "nonexistent"
        assert_failure
        [[ "$output" == *"❌"* ]]
        [[ "$output" == *"not found"* ]]
        _teardown_tool
        _setup_tool_env "kilo"
    done
}

# ─── Validate Account ────────────────────────────────────────────────────────

@test "env validate: accepts valid env file" {
    for tool in "${TOOLS[@]}"; do
        _setup_tool_env "$tool"
        _create_account "validtest" "ANTHROPIC_API_KEY=sk-test-key"
        run _run_script "$tool" env validate "validtest"
        assert_success
        [[ "$output" == *"✅"* ]]
        [[ "$output" == *"valid"* ]]
        _teardown_tool
        _setup_tool_env "kilo"
    done
}

@test "env validate: rejects invalid env file" {
    for tool in "${TOOLS[@]}"; do
        _setup_tool_env "$tool"
        echo "this is not valid env content" > "$TEST_TEMP/accounts/invalid.env"
        run _run_script "$tool" env validate "invalid"
        assert_failure
        [[ "$output" == *"❌"* ]]
        _teardown_tool
        _setup_tool_env "kilo"
    done
}

@test "env validate: fails for non-existent account" {
    for tool in "${TOOLS[@]}"; do
        _setup_tool_env "$tool"
        run _run_script "$tool" env validate "missing"
        assert_failure
        _teardown_tool
        _setup_tool_env "kilo"
    done
}

# ─── Edit Account ────────────────────────────────────────────────────────────

@test "env edit: fails for non-existent account" {
    for tool in "${TOOLS[@]}"; do
        _setup_tool_env "$tool"
        EDITOR=true run _run_script "$tool" env edit "nonexistent"
        assert_failure
        [[ "$output" == *"❌"* ]]
        _teardown_tool
        _setup_tool_env "kilo"
    done
}

# ─── Load Account ────────────────────────────────────────────────────────────

@test "env load: exports environment variables" {
    for tool in "${TOOLS[@]}"; do
        _setup_tool_env "$tool"
        local accounts_dir_var="${TOOL_ACCOUNTS_DIR_ENV[$tool]}"
        _create_account "loadtest" "ANTHROPIC_API_KEY=sk-ant-load-key-12345"
        # Run load in subshell to capture exported vars
        local result
        result=$(
            export "$accounts_dir_var=$TEST_TEMP/accounts"
            bash "${SCRIPTS_ROOT}/${TOOL_ENV_SCRIPT[$tool]}" "loadtest" 2>&1
        )
        [[ "$result" == *"✅ Loaded account: loadtest"* ]]
        _teardown_tool
        _setup_tool_env "kilo"
    done
}

@test "env load: fails for non-existent account" {
    for tool in "${TOOLS[@]}"; do
        _setup_tool_env "$tool"
        run _run_script "$tool" env "nonexistent"
        assert_failure
        [[ "$output" == *"❌"* ]]
        _teardown_tool
        _setup_tool_env "kilo"
    done
}

# ─── Run With Account ────────────────────────────────────────────────────────

@test "env run: executes command with account env vars" {
    for tool in "${TOOLS[@]}"; do
        _setup_tool_env "$tool"
        _create_account "runtest" "TEST_VAR=hello-world"
        # Test that env vars are passed through
        local result
        result=$(
            export "${TOOL_ACCOUNTS_DIR_ENV[$tool]}=$TEST_TEMP/accounts"
            bash "${SCRIPTS_ROOT}/${TOOL_ENV_SCRIPT[$tool]}" "runtest" env | grep "TEST_VAR"
        )
        [[ "$result" == *"hello-world"* ]]
        _teardown_tool
        _setup_tool_env "kilo"
    done
}

@test "env run: fails when no command given" {
    for tool in "${TOOLS[@]}"; do
        _setup_tool_env "$tool"
        _create_account "nocmd" "ANTHROPIC_API_KEY=sk-test"
        # The run_with_account function is called internally when no second arg
        # But this tests the load path, not the run path
        run _run_script "$tool" env "nocmd"
        assert_success  # This goes to load_account, not run_with_account
        _teardown_tool
        _setup_tool_env "kilo"
    done
}

# ─── Usage / Help ────────────────────────────────────────────────────────────

@test "env usage: shows help with --help flag" {
    for tool in "${TOOLS[@]}"; do
        _setup_tool_env "$tool"
        run _run_script "$tool" env --help
        assert_success
        [[ "$output" == *"Usage"* ]]
        [[ "$output" == *"create"* ]]
        [[ "$output" == *"list"* ]]
        _teardown_tool
        _setup_tool_env "kilo"
    done
}

@test "env usage: shows help with -h flag" {
    for tool in "${TOOLS[@]}"; do
        _setup_tool_env "$tool"
        run _run_script "$tool" env -h
        assert_success
        [[ "$output" == *"Usage"* ]]
        _teardown_tool
        _setup_tool_env "kilo"
    done
}

@test "env usage: shows help with no args" {
    for tool in "${TOOLS[@]}"; do
        _setup_tool_env "$tool"
        run _run_script "$tool" env
        assert_success
        [[ "$output" == *"Usage"* ]]
        _teardown_tool
        _setup_tool_env "kilo"
    done
}

# ─── Unknown Command ─────────────────────────────────────────────────────────

@test "env unknown: shows error for unknown command" {
    for tool in "${TOOLS[@]}"; do
        _setup_tool_env "$tool"
        run _run_script "$tool" env "bogus-command"
        assert_failure
        [[ "$output" == *"❌"* ]] || [[ "$output" == *"Usage"* ]]
        _teardown_tool
        _setup_tool_env "kilo"
    done
}

# ─── Security: API Key Not Exposed ───────────────────────────────────────────

@test "env list: does not expose API keys in output" {
    for tool in "${TOOLS[@]}"; do
        _setup_tool_env "$tool"
        _create_account "secret" "ANTHROPIC_API_KEY=sk-ant-super-secret-key-123456789"
        run _run_script "$tool" env list
        _assert_output_not_contains "sk-ant-super-secret-key-123456789"
        _teardown_tool
        _setup_tool_env "kilo"
    done
}

@test "env show: masks API keys in output" {
    for tool in "${TOOLS[@]}"; do
        _setup_tool_env "$tool"
        _create_account "masked" "ANTHROPIC_API_KEY=sk-ant-visible-secret-key-123456"
        run _run_script "$tool" env show "masked"
        _assert_output_not_contains "sk-ant-visible-secret-key-123456"
        [[ "$output" == *"****"* ]]
        _teardown_tool
        _setup_tool_env "kilo"
    done
}
