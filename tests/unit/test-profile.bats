#!/usr/bin/env bats
# test-profile.bats - Unit tests for all 5 profile scripts
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

# ─── Create Profile ──────────────────────────────────────────────────────────

@test "profile create: creates profile directory" {
    for tool in "${TOOLS[@]}"; do
        _setup_tool_env "$tool"
        # Set config dir for profile scripts
        export "${TOOL_CONFIG_DIR_ENV[$tool]}=$TEST_TEMP/config"
        run _run_script "$tool" profile create "test-profile"
        assert_success
        [[ "$output" == *"✅ Created profile: test-profile"* ]]
        _assert_dir_exists "$TEST_TEMP/config/profiles/test-profile"
        _teardown_tool
        _setup_tool_env "kilo"
    done
}

@test "profile create: creates config file in profile" {
    for tool in "${TOOLS[@]}"; do
        _setup_tool_env "$tool"
        export "${TOOL_CONFIG_DIR_ENV[$tool]}=$TEST_TEMP/config"
        _run_script "$tool" profile create "with-config"
        _assert_file_exists "$TEST_TEMP/config/profiles/with-config/opencode.json"
        _teardown_tool
        _setup_tool_env "kilo"
    done
}

@test "profile create: rejects empty name" {
    for tool in "${TOOLS[@]}"; do
        _setup_tool_env "$tool"
        export "${TOOL_CONFIG_DIR_ENV[$tool]}=$TEST_TEMP/config"
        run _run_script "$tool" profile create ""
        assert_failure
        [[ "$output" == *"❌"* ]]
        _teardown_tool
        _setup_tool_env "kilo"
    done
}

@test "profile create: rejects invalid characters" {
    for tool in "${TOOLS[@]}"; do
        _setup_tool_env "$tool"
        export "${TOOL_CONFIG_DIR_ENV[$tool]}=$TEST_TEMP/config"
        run _run_script "$tool" profile create "my profile"
        assert_failure
        [[ "$output" == *"❌"* ]]
        _teardown_tool
        _setup_tool_env "kilo"
    done
}

# ─── List Profiles ───────────────────────────────────────────────────────────

@test "profile list: shows all profiles" {
    for tool in "${TOOLS[@]}"; do
        _setup_tool_env "$tool"
        export "${TOOL_CONFIG_DIR_ENV[$tool]}=$TEST_TEMP/config"
        _create_profile_dir "alpha"
        _create_profile_dir "beta"
        run _run_script "$tool" profile list
        assert_success
        [[ "$output" == *"alpha"* ]]
        [[ "$output" == *"beta"* ]]
        _teardown_tool
        _setup_tool_env "kilo"
    done
}

@test "profile list: shows empty message when no profiles" {
    for tool in "${TOOLS[@]}"; do
        _setup_tool_env "$tool"
        export "${TOOL_CONFIG_DIR_ENV[$tool]}=$TEST_TEMP/config"
        run _run_script "$tool" profile list
        assert_success
        [[ "$output" == *"No profiles found"* ]]
        _teardown_tool
        _setup_tool_env "kilo"
    done
}

# ─── Switch Profile ──────────────────────────────────────────────────────────

@test "profile switch: switches to existing profile" {
    for tool in "${TOOLS[@]}"; do
        _setup_tool_env "$tool"
        export "${TOOL_CONFIG_DIR_ENV[$tool]}=$TEST_TEMP/config"
        _create_profile_dir "switchme"
        run _run_script "$tool" profile switch "switchme"
        assert_success
        [[ "$output" == *"✅ Switched to profile: switchme"* ]]
        _teardown_tool
        _setup_tool_env "kilo"
    done
}

@test "profile switch: fails for non-existent profile" {
    for tool in "${TOOLS[@]}"; do
        _setup_tool_env "$tool"
        export "${TOOL_CONFIG_DIR_ENV[$tool]}=$TEST_TEMP/config"
        run _run_script "$tool" profile switch "nonexistent"
        assert_failure
        [[ "$output" == *"❌"* ]]
        [[ "$output" == *"not found"* ]]
        _teardown_tool
        _setup_tool_env "kilo"
    done
}

@test "profile switch: rejects invalid JSON in profile config" {
    for tool in "${TOOLS[@]}"; do
        _setup_tool_env "$tool"
        export "${TOOL_CONFIG_DIR_ENV[$tool]}=$TEST_TEMP/config"
        mkdir -p "$TEST_TEMP/config/profiles/badjson"
        echo "{invalid json" > "$TEST_TEMP/config/profiles/badjson/opencode.json"
        run _run_script "$tool" profile switch "badjson"
        assert_failure
        [[ "$output" == *"❌"* ]]
        [[ "$output" == *"invalid JSON"* ]] || [[ "$output" == *"syntax"* ]]
        _teardown_tool
        _setup_tool_env "kilo"
    done
}

# ─── Delete Profile ──────────────────────────────────────────────────────────

@test "profile delete: requires confirmation (simulated with 'n')" {
    for tool in "${TOOLS[@]}"; do
        _setup_tool_env "$tool"
        export "${TOOL_CONFIG_DIR_ENV[$tool]}=$TEST_TEMP/config"
        _create_profile_dir "todelete"
        # Simulate 'n' response (can't easily test interactive, so skip)
        _teardown_tool
        _setup_tool_env "kilo"
    done
    skip "Interactive confirmation test requires input simulation"
}

@test "profile delete: fails for non-existent profile" {
    for tool in "${TOOLS[@]}"; do
        _setup_tool_env "$tool"
        export "${TOOL_CONFIG_DIR_ENV[$tool]}=$TEST_TEMP/config"
        # Cannot test interactive delete easily, skip
        _teardown_tool
        _setup_tool_env "kilo"
    done
    skip "Interactive confirmation test requires input simulation"
}

# ─── Current Profile ─────────────────────────────────────────────────────────

@test "profile current: shows no profile when none selected" {
    for tool in "${TOOLS[@]}"; do
        _setup_tool_env "$tool"
        export "${TOOL_CONFIG_DIR_ENV[$tool]}=$TEST_TEMP/config"
        run _run_script "$tool" profile current
        assert_success
        [[ "$output" == *"No profile selected"* ]] || [[ "$output" == *"default"* ]]
        _teardown_tool
        _setup_tool_env "kilo"
    done
}

# ─── Edit Profile ────────────────────────────────────────────────────────────

@test "profile edit: fails for non-existent profile" {
    for tool in "${TOOLS[@]}"; do
        _setup_tool_env "$tool"
        export "${TOOL_CONFIG_DIR_ENV[$tool]}=$TEST_TEMP/config"
        EDITOR=true run _run_script "$tool" profile edit "nonexistent"
        assert_failure
        [[ "$output" == *"❌"* ]]
        _teardown_tool
        _setup_tool_env "kilo"
    done
}

# ─── Validate Profile ────────────────────────────────────────────────────────

@test "profile validate: accepts valid profile config" {
    for tool in "${TOOLS[@]}"; do
        _setup_tool_env "$tool"
        export "${TOOL_CONFIG_DIR_ENV[$tool]}=$TEST_TEMP/config"
        _create_profile_dir "validprof"
        run _run_script "$tool" profile validate "validprof"
        assert_success
        [[ "$output" == *"✅"* ]]
        [[ "$output" == *"valid"* ]]
        _teardown_tool
        _setup_tool_env "kilo"
    done
}

@test "profile validate: rejects invalid profile config" {
    for tool in "${TOOLS[@]}"; do
        _setup_tool_env "$tool"
        export "${TOOL_CONFIG_DIR_ENV[$tool]}=$TEST_TEMP/config"
        mkdir -p "$TEST_TEMP/config/profiles/invalidprof"
        echo "{bad json" > "$TEST_TEMP/config/profiles/invalidprof/opencode.json"
        run _run_script "$tool" profile validate "invalidprof"
        assert_failure
        [[ "$output" == *"❌"* ]]
        _teardown_tool
        _setup_tool_env "kilo"
    done
}

@test "profile validate: fails for non-existent profile" {
    for tool in "${TOOLS[@]}"; do
        _setup_tool_env "$tool"
        export "${TOOL_CONFIG_DIR_ENV[$tool]}=$TEST_TEMP/config"
        run _run_script "$tool" profile validate "missingprof"
        assert_failure
        [[ "$output" == *"❌"* ]]
        _teardown_tool
        _setup_tool_env "kilo"
    done
}

# ─── Usage / Help ────────────────────────────────────────────────────────────

@test "profile usage: shows help with no args" {
    for tool in "${TOOLS[@]}"; do
        _setup_tool_env "$tool"
        run _run_script "$tool" profile
        assert_success
        [[ "$output" == *"Usage"* ]]
        [[ "$output" == *"switch"* ]]
        [[ "$output" == *"create"* ]]
        _teardown_tool
        _setup_tool_env "kilo"
    done
}

@test "profile usage: shows help with --help" {
    for tool in "${TOOLS[@]}"; do
        _setup_tool_env "$tool"
        run _run_script "$tool" profile --help
        assert_success
        [[ "$output" == *"Usage"* ]]
        _teardown_tool
        _setup_tool_env "kilo"
    done
}
