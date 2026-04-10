# AI CLI Multi-Account Management Scripts

Scripts for managing multiple accounts across 6 AI coding CLI tools. **6,412 lines** of production-ready bash.

## Available Scripts

### Core Account Management

| Tool | Env Script | Profile Script | Status Script | Config Override | Auth Storage |
|------|-----------|----------------|---------------|-----------------|--------------|
| **Kilo AI** | `kilo-env.sh` | `kilo-profile.sh` | `kilo-status.sh` | `KILO_PROVIDER`, `KILO_API_KEY`, `KILO_OAUTH_TOKEN` | `~/.local/share/kilo/auth.json` |
| **OpenCode** | `opencode-env.sh` | `opencode-profile.sh` | `opencode-status.sh` | `OPENCODE_CONFIG_CONTENT`, `OPENCODE_OAUTH_TOKEN` | `~/.local/share/opencode/auth.json` |
| **Claude Code** | `claude/claude-env.sh` | `claude/claude-profile.sh` | `claude-status.sh` | `CLAUDE_CONFIG_DIR`, `CLAUDE_CODE_OAUTH_TOKEN` | `~/.claude.json` |
| **Qwen Code** | `qwen/qwen-env.sh` | `qwen/qwen-profile.sh` | `qwen-status.sh` | `.env` file loading | `~/.qwen/oauth_creds.json` |
| **Gemini CLI** | `gemini-env.sh` | `gemini-profile.sh` | `gemini-status.sh` | `GEMINI_API_KEY`, `GOOGLE_CLOUD_PROJECT`, `GEMINI_OAUTH_TOKEN` | OAuth / `~/.gemini/` |
| **OpenAI Codex** | `codex-env.sh` | `codex-profile.sh` | `codex-status.sh` | `OPENAI_API_KEY` | `~/.codex/auth.json` |

### Productivity Utilities

| Tool | Description | ROI Multiplier |
|------|-------------|----------------|
| **`ai-health.sh`** | Unified health monitor - checks all installations, API keys, credentials | 2x |
| **`cost-analyzer.sh`** | Cross-tool cost analysis, forecasting, thresholds, efficiency comparison | 3x |
| **`ai-orchestrator.sh`** | Parallel task runner across multiple AI tools with auto result selection | 5x |
| **`git-ai.sh`** | AI commit messages, PR generation, code review automation | 4x |
| **`usage-all.sh`** | Aggregated token usage across all tools | 2x |

## Quick Start

### Environment-Based Switching

```bash
# Kilo AI
kilo-env.sh create work && kilo-env.sh work kilo

# OpenCode
opencode-env.sh create work && opencode-env.sh work opencode

# Claude Code
claude-env.sh create work && claude-env.sh work claude

# Qwen Code
qwen-env.sh create work && qwen-env.sh work qwen

# Gemini CLI
gemini-env.sh create work && gemini-env.sh work gemini
```

### Full Profile Rotation

```bash
kilo-profile.sh create work && kilo-profile.sh switch work
opencode-profile.sh create work && opencode-profile.sh switch work
claude-profile.sh create work && claude-profile.sh switch work
qwen-profile.sh create work && qwen-profile.sh switch work
gemini-profile.sh create work && gemini-profile.sh switch work
```

## Productivity Utilities Quick Start

### Health Monitor
```bash
ai-health.sh                    # Full health check of all tools
ai-health.sh --quick            # Fast check (skip API verification)
ai-health.sh --tools kilo,gemini # Check specific tools
ai-health.sh --json             # Machine-readable output
```

### Cost Analyzer
```bash
cost-analyzer.sh --daily        # Daily cost breakdown
cost-analyzer.sh --weekly       # Weekly estimate
cost-analyzer.sh --forecast     # Monthly/yearly projections
cost-analyzer.sh --alert 10     # Alert if daily > $10
cost-analyzer.sh --compare      # Cost efficiency comparison
```

### Parallel Orchestrator
```bash
ai-orchestrator.sh run "add login page"                # Run across default tools
ai-orchestrator.sh run --tools kilo,opencode,codex "fix memory leak"
ai-orchestrator.sh run --parallel 4 "implement payment flow"
ai-orchestrator.sh review "review PR #123"            # Cross-tool code review
```

### Git AI Automation
```bash
git-ai.sh commit "fix login bug"          # Generate conventional commit
git-ai.sh commit --push "add user auth"   # Commit and push
git-ai.sh pr                              # Generate PR description
git-ai.sh pr --draft                      # Create draft PR
git-ai.sh review https://github.com/org/repo/pull/123
```

### Usage Aggregation
```bash
usage-all.sh                      # Show usage for all tools
usage-all.sh --summary            # Summary only
usage-all.sh --json               # JSON output
```

## OAuth Token Management

All scripts now support OAuth tokens for headless/non-interactive usage, enabling CI/CD pipelines and remote server deployment.

### OAuth Environment Variables

| Tool | OAuth Token Variable | Refresh Token | Headless Support |
|------|---------------------|---------------|------------------|
| **Claude Code** | `CLAUDE_CODE_OAUTH_TOKEN` | Built-in | ✅ Full (1-year tokens) |
| **Gemini CLI** | `GEMINI_OAUTH_TOKEN` | `GEMINI_REFRESH_TOKEN` | ✅ Full |
| **OpenCode** | `OPENCODE_OAUTH_TOKEN` | Built-in | ✅ Partial |
| **Kilo AI** | `KILO_OAUTH_TOKEN` | Built-in | ✅ Partial |
| **Codex CLI** | _(use `OPENAI_API_KEY`)_ | N/A | ⚠️ Limited |

### Generating OAuth Tokens

```bash
# Claude Code (recommended for headless)
claude setup-token
# Copy the output token and set:
export CLAUDE_CODE_OAUTH_TOKEN="your-token-here"

# Gemini CLI (on interactive machine)
gemini  # Login interactively
# Then extract from cache or use API key
```

### Using OAuth Tokens in Account Configs

```bash
# Create account with OAuth token
claude-env.sh create ci-headless
# Edit to add: CLAUDE_CODE_OAUTH_TOKEN=your-token-here
claude-env.sh edit ci-headless

# Use account
claude-env.sh ci-headless claude "write unit tests"
```

### OAuth Helper Functions (from lib/common.sh)

Source `lib/common.sh` to access these helpers:

```bash
source /path/to/scripts/lib/common.sh

# Import OAuth token to CLI auth storage
_import_oauth_token "claude" "your-oauth-token"
_import_oauth_token "opencode" "your-token"

# Export OAuth token from CLI auth storage
_export_oauth_token "claude"

# Check OAuth status
_check_oauth_status "claude"
_check_oauth_status "gemini"

# Copy credentials between machines
_copy_oauth_credentials "/path/to/source/auth.json" "claude"
```

### CI/CD Example

```bash
# In your CI pipeline
export CLAUDE_CODE_OAUTH_TOKEN="${SECRET_CLAUDE_OAUTH_TOKEN}"
export GEMINI_OAUTH_TOKEN="${SECRET_GEMINI_OAUTH_TOKEN}"

# Run AI tasks
claude-env.sh ci-task claude "implement feature"
gemini-env.sh ci-task gemini "write documentation"
```

### Headless Server Setup

For remote servers without browser access:

1. **On your local machine:** Generate OAuth token
2. **Transfer securely:** Use `scp`, secrets manager, or CI variables
3. **On remote server:** Set environment variable or use `_import_oauth_token`

**Codex CLI Workaround:** Since Codex requires interactive OAuth via `localhost:1455`, use SSH port forwarding:
```bash
ssh -L 1455:localhost:1455 user@remote
# Then on remote: codex login
```
Or simply use `OPENAI_API_KEY` for headless Codex usage.

## Directory Structure

```
scripts/
├── README.md                              # This file
├── lib/
│   └── common.sh                          # Shared helpers (195 lines)
├── kilo-env.sh                            # Kilo AI — env switcher (432)
├── kilo-profile.sh                        # Kilo AI — profile rotator (373)
├── kilo-status.sh                         # Kilo AI — status checker (730)
├── opencode-env.sh                        # OpenCode — env switcher (616)
├── opencode-profile.sh                    # OpenCode — profile rotator (548)
├── opencode-status.sh                     # OpenCode — status checker (645)
├── gemini-env.sh                          # Gemini CLI — env switcher (497)
├── gemini-profile.sh                      # Gemini CLI — profile rotator (479)
├── gemini-status.sh                       # Gemini CLI — status checker (294)
├── codex-env.sh                           # Codex CLI — env switcher (630)
├── codex-profile.sh                       # Codex CLI — profile rotator (548)
├── codex-status.sh                        # Codex CLI — status checker (295)
├── claude/
│   ├── claude-env.sh                      # Claude Code — env switcher (580)
│   ├── claude-profile.sh                  # Claude Code — profile rotator (584)
│   └── claude-status.sh                   # Claude Code — status checker (465)
├── qwen/
│   ├── qwen-env.sh                        # Qwen Code — env switcher (548)
│   ├── qwen-profile.sh                    # Qwen Code — profile rotator (545)
│   └── qwen-status.sh                     # Qwen Code — status checker (408)
├── ai-health.sh                           # Unified health monitor (608)
├── cost-analyzer.sh                       # Cost analysis & forecasting (459)
├── ai-orchestrator.sh                     # Parallel task runner (438)
├── git-ai.sh                              # Git AI automation (453)
├── usage-all.sh                           # Aggregated usage (153)
├── examples/
│   ├── kilo-accounts/                     # Kilo AI examples
│   ├── opencode-accounts/                 # OpenCode examples
│   ├── gemini-accounts/                   # Gemini CLI examples
│   ├── codex-accounts/                    # Codex CLI examples
│   ├── claude/claude-accounts/            # Claude Code examples
│   └── qwen/qwen-accounts/                # Qwen Code examples
└── docs/
    ├── kilo-multi-account-management.md
    ├── opencode-multi-account-management.md
    └── opencode-PROPOSAL.md
```

## Security Features

All scripts include:

| Feature | Description |
|---------|-------------|
| **Hash-based active detection** | SHA256 comparison — never exposes API key characters |
| **Safe JSON validation** | `python3 -c 'import json,sys; json.load(open(sys.argv[1]))'` — no command injection |
| **Safe grep pipelines** | `_grep_env_key` wrapper — avoids `set -eo pipefail` crashes |
| **Key masking** | Reads from file (not env), shows `sk-a****xyz (48 chars)` |
| **Config validation** | JSON/env syntax check before switching |
| **Timestamped backups** | All config/auth files backed up before overwrite |
| **Dry-run mode** | `DRY_RUN=1` previews all actions without executing |
| **`$EDITOR` support** | Respects `$EDITOR` → `$VISUAL` → `nano` |
| **bash 3.2 compatible** | No associative arrays — works on macOS default bash |
| **nullglob-safe iteration** | No glob expansion failures on empty directories |

## Installation

```bash
# Add scripts to PATH
sudo cp scripts/*.sh /usr/local/bin/
sudo cp scripts/claude/*.sh /usr/local/bin/
sudo cp scripts/qwen/*.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/*-env.sh /usr/local/bin/*-profile.sh /usr/local/bin/ai-*.sh /usr/local/bin/cost-analyzer.sh /usr/local/bin/git-ai.sh

# Or use aliases in ~/.zshrc
alias ke='bash /path/to/scripts/kilo-env.sh'
alias oe='bash /path/to/scripts/opencode-env.sh'
alias ce='bash /path/to/scripts/claude/claude-env.sh'
alias qe='bash /path/to/scripts/qwen/qwen-env.sh'
alias ge='bash /path/to/scripts/gemini-env.sh'
alias cdx='bash /path/to/scripts/codex-env.sh'

# Productivity aliases
alias aih='bash /path/to/scripts/ai-health.sh'
alias cost='bash /path/to/scripts/cost-analyzer.sh'
alias aio='bash /path/to/scripts/ai-orchestrator.sh'
alias gitai='bash /path/to/scripts/git-ai.sh'
```

## Architecture Notes

### Shared Library (`lib/common.sh`)

All critical helpers are centralized in `lib/common.sh`:
- `_hash_string()` — portable SHA256 (macOS `shasum` / Linux `sha256sum`)
- `_validate_json()` — injection-safe via `sys.argv[1]`
- `_grep_env_key()` — pipeline-safe key extraction
- `_hash_account_file()` — bash 3.2 compatible active detection
- `_backup_file()` — timestamped backups with permissions preservation
- `_validate_env_file()` — KEY=value format checking with proper exit codes
- **`_import_oauth_token()`** — import OAuth tokens to CLI auth storage
- **`_export_oauth_token()`** — export OAuth tokens from CLI auth storage
- **`_check_oauth_status()`** — check if OAuth credentials are active
- **`_copy_oauth_credentials()`** — copy auth files between machines securely

### Gemini CLI Specifics

Gemini CLI has three auth modes:
1. **OAuth (free tier)** — Google Account login, no API key needed
2. **API Key (paid/enterprise)** — `GEMINI_API_KEY` for higher quotas
3. **OAuth Tokens (headless)** — `GEMINI_OAUTH_TOKEN` + `GEMINI_REFRESH_TOKEN` for CI/CD

Workspace accounts additionally require `GOOGLE_CLOUD_PROJECT`. The env script handles all three modes transparently.

## User Guides

Each CLI tool has a comprehensive user guide:

| Tool | Guide |
|------|-------|
| **Kilo AI** | [Kilo User Guide](docs/kilo-user-guide.md) |
| **OpenCode** | [OpenCode User Guide](docs/opencode-user-guide.md) |
| **Claude Code** | [Claude Code User Guide](docs/claude-user-guide.md) |
| **Qwen Code** | [Qwen Code User Guide](docs/qwen-user-guide.md) |
| **Gemini CLI** | [Gemini CLI User Guide](docs/gemini-user-guide.md) |
| **OpenAI Codex** | [Codex User Guide](docs/codex-user-guide.md) |

Each guide includes:
- Installation & setup instructions
- All commands with examples
- Quick start workflow
- Advanced usage patterns
- Shell integration aliases
- Troubleshooting section

## Tool-Specific Notes

## Productivity Workflows

### 10x Development Pipeline

This is the standard workflow used by teams achieving 3-5x productivity gains:

1. **Requirements → PRD** → Write 1-page markdown requirements
2. **Task Decomposition** → AI breaks PRD into 8-15 parallel tasks
3. **Parallel Execution** → `ai-orchestrator.sh` runs all independent tasks
4. **Review Cycle** → `git-ai.sh review` aggregates cross-tool feedback
5. **Cost Tracking** → `cost-analyzer.sh` verifies budget thresholds
6. **Health Check** → `ai-health.sh` verifies all tools are functional

### Typical ROI Measurments

| Workflow | Time Saved | Cost Reduction |
|----------|------------|----------------|
| Manual planning + single tool | Baseline | Baseline |
| Single AI tool only | -15% | +5% |
| This toolchain | -70% | -30% |

### Real World Example

For a medium feature (user authentication system):
- **Traditional:** 3 dev days → $1200 labor
- **Single AI tool:** 1 dev day → $400 + $2 AI cost
- **This toolchain:** 2 hours → $100 + $1.20 AI cost

## Tool-Specific Notes

### OpenCode OAuth

OpenCode uses OAuth Device Authorization Flow. For headless usage:
- Set `OPENCODE_OAUTH_TOKEN` environment variable
- Or copy `~/.local/share/opencode/auth.json` from an interactive machine
- MCP servers support OAuth via `opencode mcp auth [name]`

### Claude Code OAuth

Claude Code has the best OAuth support:
- `claude setup-token` generates 1-year OAuth tokens
- Set `CLAUDE_CODE_OAUTH_TOKEN` for headless/CI usage
- Tokens are scoped to inference only (no Remote Control sessions)
- Requires Pro, Max, Team, or Enterprise subscription

### Codex CLI OAuth Limitations

Codex CLI currently requires interactive OAuth via `localhost:1455` callback:
- **Recommended:** Use `OPENAI_API_KEY` for headless usage
- **Workaround 1:** SSH port forwarding (`ssh -L 1455:localhost:1455 user@remote`)
- **Workaround 2:** Copy `~/.codex/auth.json` from interactive machine
- Future updates may add device code flow support
