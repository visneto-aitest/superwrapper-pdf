# AI CLI Multi-Account Management Scripts

Scripts for managing multiple accounts across 6 AI coding CLI tools. Production-ready bash scripts.

## Core Account Management

| Script | Purpose | Reference |
|--------|---------|-----------|
| `kilo-env.sh` | Switch environment for Kilo AI | [Kilo Env Docs](docs/kilo-env.md) |
| `kilo-profile.sh` | Manage Kilo AI profiles | [Kilo Profile Docs](docs/kilo-profile.md) |
| `kilo-status.sh` | Check status of Kilo AI accounts | [Kilo Status Docs](docs/kilo-status.md) |
| `opencode-env.sh` | Switch environment for OpenCode | [OpenCode Env Docs](docs/opencode-env.md) |
| `opencode-profile.sh` | Manage OpenCode profiles | [OpenCode Profile Docs](docs/opencode-profile.md) |
| `opencode-status.sh` | Check status of OpenCode accounts | [OpenCode Status Docs](docs/opencode-status.md) |
| `claude-env.sh` | Switch environment for Claude Code | [Claude Env Docs](docs/claude-env.md) |
| `claude-profile.sh` | Manage Claude Code profiles | [Claude Profile Docs](docs/claude-profile.md) |
| `claude-status.sh` | Check status of Claude Code accounts | [Claude Status Docs](docs/claude-status.md) |
| `qwen-env.sh` | Switch environment for Qwen Code | [Qwen Env Docs](docs/qwen-env.md) |
| `qwen-profile.sh` | Manage Qwen Code profiles | [Qwen Profile Docs](docs/qwen-profile.md) |
| `qwen-status.sh` | Check status of Qwen Code accounts | [Qwen Status Docs](docs/qwen-status.md) |
| `gemini-env.sh` | Switch environment for Gemini CLI | [Gemini Env Docs](docs/gemini-env.md) |
| `gemini-profile.sh` | Manage Gemini CLI profiles | [Gemini Profile Docs](docs/gemini-profile.md) |
| `gemini-status.sh` | Check status of Gemini CLI accounts | [Gemini Status Docs](docs/gemini-status.md) |
| `codex-env.sh` | Switch environment for OpenAI Codex | [Codex Env Docs](docs/codex-env.md) |
| `codex-profile.sh` | Manage Codex profiles | [Codex Profile Docs](docs/codex-profile.md) |
| `codex-status.sh` | Check status of Codex accounts | [Codex Status Docs](docs/codex-status.md) |

## Productivity Utilities

| Script | Purpose | Reference |
|--------|---------|-----------|
| `ai-health.sh` | Unified health monitor for all tools | [Health Monitor Docs](docs/ai-health.md) |
| `cost-analyzer.sh` | Cost analysis, forecasting, and efficiency comparison | [Cost Analyzer Docs](docs/cost-analyzer.md) |
| `ai-orchestrator.sh` | Parallel task runner across multiple AI tools | [Orchestrator Docs](docs/ai-orchestrator.md) |
| `git-ai.sh` | Git AI automation: commit messages, PR generation, code review | [Git AI Docs](docs/git-ai.md) |
| `usage-all.sh` | Aggregated token usage across all tools | [Usage All Docs](docs/usage-all.md) |
| `add-all-aliases.sh` | Install shell aliases for all scripts | — |
| `clear-kilo-storage.sh` | Clear Kilo AI authentication storage | — |
| `clear-opencode-storage.sh` | Clear OpenCode authentication storage | — |
| `logs_cleanup.sh` | Clean up log files | — |
| `clear-sessions.sh` | Clear active sessions | — |

## Quick Start

### Environment-Based Switching
```bash
# Kilo AI
kilo-env.sh create work && kilo-env.sh work kilo

# OpenCode
opencode-env.sh create work && opencode-env.sh work opencode
# ... (similar for other tools)
```

### Full Profile Rotation
```bash
kilo-profile.sh create work && kilo-profile.sh switch work
opencode-profile.sh create work && opencode-profile.sh switch work
# ... (similar for other tools)
```

## OAuth Token Management

All scripts support OAuth tokens for headless usage. See [OAuth Management Guide](docs/oauth-management.md) for details.

## Directory Structure

```
scripts/
├── README.md                  # This file
├── lib/
│   └── common.sh              # Shared helpers
├── kilo-env.sh                # Kilo AI env switcher
├── kilo-profile.sh            # Kilo AI profile rotator
├── kilo-status.sh             # Kilo AI status checker
├── opencode-env.sh            # OpenCode env switcher
├── opencode-profile.sh        # OpenCode profile rotator
├── opencode-status.sh         # OpenCode status checker
├── claude/
│   ├── claude-env.sh          # Claude Code env switcher
│   ├── claude-profile.sh      # Claude Code profile rotator
│   └── claude-status.sh       # Claude Code status checker
├── qwen/
│   ├── qwen-env.sh            # Qwen Code env switcher
│   ├── qwen-profile.sh        # Qwen Code profile rotator
│   └── qwen-status.sh         # Qwen Code status checker
├── ai-health.sh                 # Unified health monitor
├── cost-analyzer.sh           # Cost analysis & forecasting
├── ai-orchestrator.sh         # Parallel task runner
├── git-ai.sh                  # Git AI automation
├── usage-all.sh               # Token usage aggregation
├── examples/
│   ├── kilo-accounts/         # Kilo AI example configs
│   └── ...
└── docs/
    ├── kilo-user-guide.md
    └── ...
```

## Security Features

- Hash-based active detection
- Safe JSON validation
- Safe grep pipelines
- Key masking
- Config validation
- Timestamped backups
- Dry-run mode
- `$EDITOR` support
- bash 3.2 compatible
- nullglob-safe iteration

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
alias aih='bash /path/to/scripts/ai-health.sh'
alias cost='bash /path/to/scripts/cost-analyzer.sh'
alias aio='bash /path/to/scripts/ai-orchestrator.sh'
alias gitai='bash /path/to/scripts/git-ai.sh'
```

## Architecture Notes

### Shared Library (`lib/common.sh`)
- `_hash_string()` — portable SHA256
- `_validate_json()` — injection-safe
- `_import_oauth_token()` — import OAuth tokens
- `_export_oauth_token()` — export OAuth tokens
- `_check_oauth_status()` — check OAuth status
- `_copy_oauth_credentials()` — copy credentials securely
- Additional helpers for JSON validation, backup, and dry-run

## User Guides

Each CLI tool has a comprehensive user guide in the `docs/` directory:
- [Kilo User Guide](docs/kilo-user-guide.md)
- [OpenCode User Guide](docs/opencode-user-guide.md)
- [Claude Code User Guide](docs/claude-user-guide.md)
- [Qwen Code User Guide](docs/qwen-user-guide.md)
- [Gemini CLI User Guide](docs/gemini-user-guide.md)
- [Codex User Guide](docs/codex-user-guide.md)

## Tool-Specific Notes

- **OpenCode OAuth**: Device Authorization Flow; set `OPENCODE_OAUTH_TOKEN` or copy `~/.local/share/opencode/auth.json`.
- **Claude Code OAuth**: Device flow with 1-year tokens; set `CLAUDE_CODE_OAUTH_TOKEN`.
- **Codex CLI**: Requires interactive OAuth via `localhost:1455`; use `OPENAI_API_KEY` for headless usage or SSH port forwarding.

## Productivity Workflows

### 10x Development Pipeline
1. Requirements → PRD
2. Task Decomposition → AI breaks PRD into parallel tasks
3. Parallel Execution → `ai-orchestrator.sh` runs tasks
4. Review Cycle → `git-ai.sh review` aggregates feedback
5. Cost Tracking → `cost-analyzer.sh` verifies budget
6. Health Check → `ai-health.sh` verifies tools

(End of file)