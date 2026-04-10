# Test Fixtures

Pre-built test data for unit tests.

## Directory Structure

```
fixtures/
├── accounts/          # Pre-built .env test accounts
├── sessions/          # Fake session JSON files for usage tests
├── config-valid/      # Valid JSON config files
└── config-invalid/    # Broken JSON files for validation tests
```

## Usage

Tests copy fixtures to temporary directories during `setup()` to avoid modifying source files.

```bash
cp tests/fixtures/accounts/work.env.example "$TEST_TEMP/accounts/work.env"
cp tests/fixtures/config-valid/opencode.json "$TEST_TEMP/config/opencode.json"
```

## Adding New Fixtures

1. Create fixture file in appropriate subdirectory
2. Reference it in test using `cp` to temp directory
3. Never modify fixtures in-place during tests
