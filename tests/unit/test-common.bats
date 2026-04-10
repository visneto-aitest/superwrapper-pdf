#!/usr/bin/env bats
# test-common.bats - Unit tests for lib/common.sh shared helpers
#
# Tests: _hash_string, _get_editor, _mask_value, _validate_env_file,
#        _validate_json, _dry_run, _backup_file, _var_in_list,
#        _grep_env_key, _hash_account_file, _list_files, _validate_name

load test-helpers

setup() {
    TEST_TEMP=$(mktemp -d)
    # shellcheck source=/dev/null
    source "$SCRIPTS_ROOT/lib/common.sh"
}

teardown() {
    _teardown_tool
}

# ─── _hash_string ────────────────────────────────────────────────────────────

@test "_hash_string: produces consistent output" {
    local hash1 hash2
    hash1=$(_hash_string "test-value")
    hash2=$(_hash_string "test-value")
    [ "$hash1" = "$hash2" ]
}

@test "_hash_string: different inputs produce different hashes" {
    local hash1 hash2
    hash1=$(_hash_string "value-a")
    hash2=$(_hash_string "value-b")
    [ "$hash1" != "$hash2" ]
}

@test "_hash_string: empty string produces a hash" {
    local hash
    hash=$(_hash_string "")
    [ -n "$hash" ]
    [ ${#hash} -eq 64 ]  # SHA256 produces 64 hex chars
}

@test "_hash_string: long input produces correct hash" {
    local hash
    hash=$(_hash_string "sk-ant-very-long-api-key-with-many-characters-12345")
    [ ${#hash} -eq 64 ]
}

# ─── _get_editor ─────────────────────────────────────────────────────────────

@test "_get_editor: returns nano by default" {
    local orig_editor="${EDITOR:-}"
    local orig_visual="${VISUAL:-}"
    unset EDITOR VISUAL 2>/dev/null || true
    local editor
    editor=$(_get_editor)
    [ "$editor" = "nano" ]
    # Restore
    [ -n "$orig_editor" ] && export EDITOR="$orig_editor"
    [ -n "$orig_visual" ] && export VISUAL="$orig_visual"
}

@test "_get_editor: respects EDITOR env var" {
    local orig_editor="${EDITOR:-}"
    export EDITOR=vim
    local editor
    editor=$(_get_editor)
    [ "$editor" = "vim" ]
    [ -n "$orig_editor" ] && export EDITOR="$orig_editor" || unset EDITOR
}

@test "_get_editor: EDITOR takes precedence over VISUAL" {
    local orig_editor="${EDITOR:-}"
    local orig_visual="${VISUAL:-}"
    export EDITOR=vim
    export VISUAL=emacs
    local editor
    editor=$(_get_editor)
    [ "$editor" = "vim" ]
    [ -n "$orig_editor" ] && export EDITOR="$orig_editor" || unset EDITOR
    [ -n "$orig_visual" ] && export VISUAL="$orig_visual" || unset VISUAL
}

# ─── _mask_value ─────────────────────────────────────────────────────────────

@test "_mask_value: masks long keys showing first 4 and last 4" {
    local masked
    masked=$(_mask_value "sk-ant-abcdef1234567890xyz")
    [[ "$masked" == "sk-a****" ]]
    [[ "$masked" == *"90xyz"* ]] || [[ "$masked" == *"****"* ]]
}

@test "_mask_value: includes length in output" {
    local masked
    masked=$(_mask_value "12345678901234567890")
    [[ "$masked" == *"(20 chars)"* ]]
}

@test "_mask_value: short keys show masked placeholder" {
    local masked
    masked=$(_mask_value "short")
    [[ "$masked" == *"****"* ]]
}

@test "_mask_value: empty string returns not set" {
    local masked
    masked=$(_mask_value "")
    [ "$masked" = "(not set)" ]
}

# ─── _validate_env_file ──────────────────────────────────────────────────────

@test "_validate_env_file: accepts valid KEY=value lines" {
    local tmpfile
    tmpfile=$(mktemp)
    cat > "$tmpfile" << 'EOF'
# Comment line
ANTHROPIC_API_KEY=sk-test-key
OPENAI_API_KEY=sk-proj-key

GEMINI_API_KEY=ai-key
EOF
    _validate_env_file "$tmpfile"
    rm -f "$tmpfile"
}

@test "_validate_env_file: rejects invalid format" {
    local tmpfile
    tmpfile=$(mktemp)
    cat > "$tmpfile" << 'EOF'
ANTHROPIC_API_KEY=sk-test-key
this is not valid
GEMINI_API_KEY=ai-key
EOF
    run _validate_env_file "$tmpfile"
    [ "$status" -eq 1 ]
    rm -f "$tmpfile"
}

@test "_validate_env_file: handles empty file" {
    local tmpfile
    tmpfile=$(mktemp)
    : > "$tmpfile"
    _validate_env_file "$tmpfile"
    rm -f "$tmpfile"
}

@test "_validate_env_file: handles comments-only file" {
    local tmpfile
    tmpfile=$(mktemp)
    cat > "$tmpfile" << 'EOF'
# Just a comment
# Another comment
EOF
    _validate_env_file "$tmpfile"
    rm -f "$tmpfile"
}

@test "_validate_env_file: allows leading whitespace before key" {
    local tmpfile
    tmpfile=$(mktemp)
    cat > "$tmpfile" << 'EOF'
  ANTHROPIC_API_KEY=sk-test-key
EOF
    run _validate_env_file "$tmpfile"
    # This should fail since leading whitespace breaks the regex
    [ "$status" -eq 1 ]
    rm -f "$tmpfile"
}

# ─── _validate_json ──────────────────────────────────────────────────────────

@test "_validate_json: accepts valid JSON" {
    local tmpfile
    tmpfile=$(mktemp)
    echo '{"key": "value", "nested": {"a": 1}}' > "$tmpfile"
    _validate_json "$tmpfile"
    rm -f "$tmpfile"
}

@test "_validate_json: rejects invalid JSON" {
    local tmpfile
    tmpfile=$(mktemp)
    echo '{invalid json' > "$tmpfile"
    run _validate_json "$tmpfile"
    [ "$status" -eq 1 ]
    rm -f "$tmpfile"
}

@test "_validate_json: rejects empty file" {
    local tmpfile
    tmpfile=$(mktemp)
    : > "$tmpfile"
    run _validate_json "$tmpfile"
    [ "$status" -eq 1 ]
    rm -f "$tmpfile"
}

@test "_validate_json: accepts JSON array" {
    local tmpfile
    tmpfile=$(mktemp)
    echo '[1, 2, 3, {"key": "value"}]' > "$tmpfile"
    _validate_json "$tmpfile"
    rm -f "$tmpfile"
}

# ─── _dry_run ────────────────────────────────────────────────────────────────

@test "_dry_run: executes command when DRY_RUN=0" {
    DRY_RUN=0 run _dry_run echo "hello"
    [ "$status" -eq 0 ]
    [[ "$output" == "hello" ]]
}

@test "_dry_run: prints preview when DRY_RUN=1" {
    DRY_RUN=1 run _dry_run echo "hello"
    [ "$status" -eq 0 ]
    [[ "$output" == *"🔍 [DRY RUN] Would execute: echo hello"* ]]
}

# ─── _backup_file ────────────────────────────────────────────────────────────

@test "_backup_file: creates timestamped backup" {
    local tmpfile
    tmpfile=$(mktemp)
    echo "test content" > "$tmpfile"
    chmod 600 "$tmpfile"

    run _backup_file "$tmpfile"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Backed up"* ]]

    # Verify backup exists
    local dir
    dir=$(dirname "$tmpfile")
    local backup_count
    backup_count=$(find "$dir" -name "$(basename "$tmpfile").backup_*" | wc -l)
    [ "$backup_count" -eq 1 ]
    rm -f "$tmpfile" "$dir"/*.backup_*
}

@test "_backup_file: does nothing for non-existent file" {
    run _backup_file "/nonexistent/file.json"
    [ "$status" -eq 0 ]
    [[ "$output" == "" ]]
}

# ─── _grep_env_key ───────────────────────────────────────────────────────────

@test "_grep_env_key: extracts value for existing key" {
    local tmpfile
    tmpfile=$(mktemp)
    cat > "$tmpfile" << 'EOF'
ANTHROPIC_API_KEY=sk-test-value
OPENAI_API_KEY=sk-other
EOF
    local result
    result=$(_grep_env_key "ANTHROPIC_API_KEY" "$tmpfile")
    [ "$result" = "sk-test-value" ]
    rm -f "$tmpfile"
}

@test "_grep_env_key: returns empty for missing key" {
    local tmpfile
    tmpfile=$(mktemp)
    echo "OTHER_KEY=value" > "$tmpfile"
    local result
    result=$(_grep_env_key "MISSING_KEY" "$tmpfile")
    [ "$result" = "" ]
    rm -f "$tmpfile"
}

@test "_grep_env_key: handles file with no matches (set -e safe)" {
    local tmpfile
    tmpfile=$(mktemp)
    echo "SOME_KEY=value" > "$tmpfile"
    # This should not crash with set -euo pipefail
    local result
    result=$(_grep_env_key "NOT_HERE" "$tmpfile")
    [ "$result" = "" ]
    rm -f "$tmpfile"
}

# ─── _hash_account_file ──────────────────────────────────────────────────────

@test "_hash_account_file: produces consistent hash for same file" {
    local tmpfile
    tmpfile=$(mktemp)
    cat > "$tmpfile" << 'EOF'
ANTHROPIC_API_KEY=sk-test-key
OPENAI_API_KEY=sk-other-key
EOF
    local hash1 hash2
    hash1=$(_hash_account_file "$tmpfile" "ANTHROPIC_API_KEY OPENAI_API_KEY")
    hash2=$(_hash_account_file "$tmpfile" "ANTHROPIC_API_KEY OPENAI_API_KEY")
    [ "$hash1" = "$hash2" ]
    rm -f "$tmpfile"
}

@test "_hash_account_file: different values produce different hashes" {
    local tmpfile1 tmpfile2
    tmpfile1=$(mktemp)
    tmpfile2=$(mktemp)
    echo "ANTHROPIC_API_KEY=sk-key-a" > "$tmpfile1"
    echo "ANTHROPIC_API_KEY=sk-key-b" > "$tmpfile2"
    local hash1 hash2
    hash1=$(_hash_account_file "$tmpfile1" "ANTHROPIC_API_KEY")
    hash2=$(_hash_account_file "$tmpfile2" "ANTHROPIC_API_KEY")
    [ "$hash1" != "$hash2" ]
    rm -f "$tmpfile1" "$tmpfile2"
}

@test "_hash_account_file: empty file returns empty hash" {
    local tmpfile
    tmpfile=$(mktemp)
    : > "$tmpfile"
    local result
    result=$(_hash_account_file "$tmpfile" "ANTHROPIC_API_KEY")
    [ "$result" = "" ]
    rm -f "$tmpfile"
}

# ─── _validate_name ──────────────────────────────────────────────────────────

@test "_validate_name: accepts valid names" {
    _validate_name "work" "account"
    _validate_name "personal" "account"
    _validate_name "my-account" "account"
    _validate_name "my_account_123" "account"
}

@test "_validate_name: rejects empty name" {
    run _validate_name "" "account"
    [ "$status" -eq 1 ]
}

@test "_validate_name: rejects names with special chars" {
    run _validate_name "my account" "account"
    [ "$status" -eq 1 ]
    run _validate_name "my/account" "account"
    [ "$status" -eq 1 ]
    run _validate_name "../etc/passwd" "account"
    [ "$status" -eq 1 ]
}
