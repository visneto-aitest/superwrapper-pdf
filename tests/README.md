# AI CLI Tool Unit Tests

Comprehensive unit tests for all 15 scripts across 5 AI CLI tools.

## Quick Start

```bash
# Install bats
brew install bats-core        # macOS
sudo apt install bats         # Ubuntu/Debian

# Run all tests
bats tests/unit/

# Run specific test file
bats tests/unit/test-common.bats
bats tests/unit/test-env.bats
bats tests/unit/test-profile.bats
bats tests/unit/test-status.bats

# Run with verbose output
bats --print-output-on-failure tests/unit/

# Run single test
bats tests/unit/test-common.bats --filter "hash_string"
```

## Test Coverage

| Test File | Tests | Covers |
|-----------|-------|--------|
| `test-common.bats` | 32 | Shared library: hash, mask, validate, grep, dry-run, backup, name validation |
| `test-env.bats` | 30×5=150 | All 5 env scripts: create, list, show, edit, validate, load, run, help, security |
| `test-profile.bats` | 20×5=100 | All 5 profile scripts: create, list, switch, delete, current, edit, validate, help |
| `test-status.bats` | 16×5=80 | All 5 status scripts: full status, providers, usage, sessions, rate-limits, json, security |
| **Total** | **~362** | 15 scripts × 5 tools |

## Test Structure

```
tests/
├── test-helpers.bash          # Shared test functions & tool configuration
├── bats.conf                  # Bats configuration
├── unit/
│   ├── test-common.bats       # Shared library tests (tool-agnostic)
│   ├── test-env.bats          # Env script tests (parameterized ×5 tools)
│   ├── test-profile.bats      # Profile script tests (parameterized ×5 tools)
│   └── test-status.bats       # Status script tests (parameterized ×5 tools)
├── fixtures/
│   ├── README.md              # Fixture documentation
│   ├── accounts/              # Pre-built .env test accounts
│   ├── sessions/              # Fake session JSON for usage tests
│   ├── config-valid/          # Valid config files
│   └── config-invalid/        # Broken JSON for validation tests
└── mocks/
    └── mock-curl              # Curl mock for API verification tests
```

## How Parameterized Tests Work

Each test in `test-env.bats`, `test-profile.bats`, and `test-status.bats` loops through all 5 tools:

```bash
TOOLS=(kilo opencode claude qwen gemini)

@test "env create: creates account file for all tools" {
    for tool in "${TOOLS[@]}"; do
        _setup_tool_env "$tool"           # Sets up temp dirs + tool-specific vars
        run _run_script "$tool" env create "test"
        assert_success
        _teardown_tool
        _setup_tool_env "kilo"            # Reset for next iteration
    done
}
```

This ensures identical behavior across all tools with a single test definition.

## Test Categories

### 1. Core Functionality
- **create** — Creates account/profile, validates input, rejects duplicates
- **list** — Shows all items, handles empty state, shows correct directory
- **show** — Displays info with masked keys, fails for missing items
- **switch** — Switches active profile, validates JSON, handles missing profiles
- **validate** — Accepts valid configs, rejects invalid JSON/env

### 2. Security
- **API keys never exposed** in stdout (masked in show/list/status)
- **File permissions** set to 600 on credential files
- **Hash-based detection** — no raw key comparison in active detection
- **Input sanitization** — rejects names with path traversal (`../`)

### 3. Error Handling
- Missing arguments → helpful error messages
- Non-existent accounts/profiles → clear error with suggestions
- Invalid JSON/env syntax → validation failures with line numbers
- Network failures → graceful degradation in status scripts

### 4. Edge Cases
- Empty directories
- Missing config files
- Empty account files
- Special characters in input (rejected)
- No sessions data (graceful "no data" message)

## Fixtures

Test fixtures are pre-built data files copied to isolated temp directories during `setup()`:

| Fixture | Purpose |
|---------|---------|
| `fixtures/accounts/*.env` | Pre-configured test accounts |
| `fixtures/sessions/*.json` | Fake session data for usage tests |
| `fixtures/config-valid/*.json` | Valid JSON for positive tests |
| `fixtures/config-invalid/*.json` | Broken JSON for negative tests |

## Mocks

| Mock | Purpose |
|------|---------|
| `mocks/mock-curl` | Simulates API responses for provider verification tests. Set `MOCK_CURL_RESPONSE` to `200`, `401`, `429`, or `fail`. |

## CI Integration

```yaml
# GitHub Actions
- name: Run tests
  run: |
    brew install bats-core  # or apt install bats
    bats --print-output-on-failure tests/unit/
```

## Adding New Tests

1. Add test to appropriate `test-*.bats` file
2. Use `_setup_tool_env "$tool"` to set up temp directory
3. Use `_run_script "$tool" <type> <args...>` to run the script
4. Use `assert_success` / `assert_failure` and `[[ "$output" == *"expected"* ]]`
5. Call `_teardown_tool` and `_setup_tool_env "kilo"` to reset for next tool

## Troubleshooting

**"bats: command not found"**
```bash
brew install bats-core    # macOS
sudo apt install bats     # Ubuntu
```

**Tests fail with "No such file or directory"**
```bash
# Verify SCRIPTS_ROOT points to correct location
export SCRIPTS_ROOT=/path/to/your/scripts
bats tests/unit/
```

**Temp directories not cleaned up**
```bash
# Check that _teardown_tool is called in teardown()
# Or manually clean: rm -rf /tmp/tmp.*
```
