# Kilo AI CLI — Multi-Account User Guide

## Overview

Kilo AI CLI (built on OpenCode) manages accounts via environment variables or full config directory rotation.

**Config locations:**
- Global: `~/.config/kilo/opencode.json`
- Project: `./opencode.json` (overrides global)
- Auth: `~/.local/share/kilo/auth.json`

**Key environment variables:**
| Variable | Purpose |
|----------|---------|
| `KILO_PROVIDER` | Override provider (`openai`, `anthropic`, etc.) |
| `KILO_API_KEY` | API key for the provider |
| `KILO_MODEL` | Default model override |
| `KILO_ORG_ID` | Organization ID (Kilo Gateway) |
| `KILOCODE_MODEL` | Gateway model override |
| `KILO_CONFIG_CONTENT` | Full JSON config injection (highest priority) |

---

## Script 1: `kilo-env.sh` — Environment-Based Switching

**Best for:** Quick switching between accounts with different API keys in the same terminal.

### Installation

```bash
# Add to PATH
sudo cp /path/to/scripts/kilo-env.sh /usr/local/bin/kilo-env
sudo chmod +x /usr/local/bin/kilo-env

# Or use an alias in ~/.zshrc
alias kilo-env='bash /path/to/scripts/kilo-env.sh'
```

### Commands

| Command | Description |
|---------|-------------|
| `kilo-env list` | List all accounts with provider/model info |
| `kilo-env create <name>` | Create new account with `.env` template |
| `kilo-env show <name>` | Show account config (keys masked) |
| `kilo-env edit <name>` | Open account file in `$EDITOR` |
| `kilo-env validate <name>` | Check env file syntax |
| `kilo-env <name>` | Export vars to current shell |
| `kilo-env <name> kilo` | Run kilo with that account's credentials |

### Quick Start

```bash
# 1. Create accounts
kilo-env create work
kilo-env create personal

# 2. Edit and add API keys
kilo-env edit work      # Opens in $EDITOR
kilo-env edit personal

# 3. Example account file (~/.config/kilo/accounts/work.env):
#   KILO_PROVIDER=openai
#   KILO_API_KEY=sk-proj-work-key
#   KILO_MODEL=gpt-4-turbo

# 4. Use accounts
kilo-env work           # Export vars to current shell
kilo                    # Start Kilo with work credentials

# Or one-shot
kilo-env work kilo                    # Run with work account
kilo-env personal kilo --verbose      # Run with personal account
```

### Daily Workflow

```bash
# Morning — work mode
kilo-env work
cd ~/projects/company-repo
kilo

# Evening — personal mode
kilo-env personal
cd ~/side-project
kilo
```

---

## Script 2: `kilo-profile.sh` — Full Config Profile Rotation

**Best for:** Complete isolation — different providers, models, permissions, and MCP servers.

### Installation

```bash
sudo cp /path/to/scripts/kilo-profile.sh /usr/local/bin/kilo-profile
sudo chmod +x /usr/local/bin/kilo-profile
```

### Commands

| Command | Description |
|---------|-------------|
| `kilo-profile list` | List profiles with model/providers |
| `kilo-profile create <name>` | Create profile from current config |
| `kilo-profile switch <name>` | Switch to a profile (with JSON validation) |
| `kilo-profile delete <name>` | Delete a profile (with confirmation) |
| `kilo-profile current` | Show active profile |
| `kilo-profile edit <name>` | Edit profile config in `$EDITOR` |
| `kilo-profile validate <name>` | Validate profile JSON |

### Profile Structure

```
~/.config/kilo/profiles/
├── work/
│   ├── opencode.json      # Full work config
│   └── auth.json          # Work auth tokens
└── personal/
    ├── opencode.json      # Personal config
    └── auth.json          # Personal auth
```

### Quick Start

```bash
# 1. Set up default config first
kilo                          # Configure with primary account

# 2. Create profiles
kilo-profile create work
kilo-profile create personal

# 3. Edit each profile
kilo-profile edit work        # Modify providers, models, permissions
kilo-profile edit personal

# 4. Switch profiles
kilo-profile switch work
kilo                          # Runs with work profile

kilo-profile switch personal
kilo                          # Runs with personal profile
```

---

## Script 3: `kilo-status.sh` — Token Usage & Rate Limit Status

**Best for:** Checking Kilo Pass balance, token usage across sessions, provider auth status, and rate limit information.

> **Note:** Kilo CLI has no native `kilo usage` or `kilo status` command. This script fills that gap by querying the Kilo Gateway API, parsing session data, and checking config files.

### Installation

```bash
sudo cp /path/to/scripts/kilo-status.sh /usr/local/bin/kilo-status
sudo chmod +x /usr/local/bin/kilo-status
# Or alias in ~/.zshrc
alias ks='bash /path/to/scripts/kilo-status.sh'
```

### Commands

| Command | Description |
|---------|-------------|
| `kilo-status` | Show full status (balance + providers + usage) |
| `kilo-status --balance` | Check Kilo Pass balance only |
| `kilo-status --usage` | Show session token usage summary |
| `kilo-status --sessions` | List recent sessions with token counts |
| `kilo-status --provider <name>` | Check specific provider auth status |
| `kilo-status --rate-limits` | Show rate limit information |
| `kilo-status --json` | Output full status as JSON |

### Quick Start

```bash
# Full status report
kilo-status
# Output:
# ═══════════════════════════════════════════════════
#   Kilo AI CLI — Status Report
# ═══════════════════════════════════════════════════
#
# Configuration:
#   Config: /Users/kong/.config/kilo/opencode.json
#   Model:  anthropic/claude-sonnet-4-20250514
#
# Checking Kilo Pass balance...
# ┌─────────────────────────────────────┐
# │       Kilo Pass Balance             │
# ├─────────────────────────────────────┤
# │  Credits:         15.42            │
# │  Used:             4.58            │
# │  Total:           20.00            │
# │  Currency:        USD              │
# └─────────────────────────────────────┘
#
# Provider Status:
#   ✅ anthropic: sk-a****xyz
#   ✅ openai: sk-p****key
#
# Session Token Usage:
#   Last 20 sessions:
#   ┌─────────────────────────────────────────────┐
#   │  Input:      125.3K tokens                  │
#   │  Output:     45.7K tokens                   │
#   │  Cache Write: 12.1K tokens                  │
#   │  Cache Hit:   38.2K tokens                  │
#   │  Est. Cost:   $0.87                         │
#   └─────────────────────────────────────────────┘
#
# Dashboard: https://app.kilo.ai/dashboard

# Check balance only
kilo-status --balance

# Check token usage
kilo-status --usage

# List sessions with token counts
kilo-status --sessions
# Output:
# Recent Sessions (last 20):
# Time                     Model                Input        Output       Cost
# ----                     -----                -----        ------       ----
# 2026-04-08 14:30:22      claude-sonnet-4      2.1K         845          $0.03
# 2026-04-08 13:15:10      gpt-4-turbo          5.8K         1.2K         $0.12
# ...

# Check specific provider
kilo-status --provider anthropic
# Output:
#   ✅ anthropic: sk-a****xyz

# Rate limit info
kilo-status --rate-limits
# Output:
#   Free Models:     200 requests per 5 hours per IP
#   Paid Models:     No gateway-enforced limits

# JSON output (for scripting/monitoring)
kilo-status --json
# Output:
# {
#   "config_file": "/Users/kong/.config/kilo/opencode.json",
#   "providers": {
#     "anthropic": { "enabled": true, "has_key": true },
#     "openai": { "enabled": true, "has_key": true }
#   },
#   "session_summary": {
#     "sessions_analyzed": 20,
#     "total_input_tokens": 125300,
#     "total_output_tokens": 45700,
#     "estimated_cost_usd": 0.87
#   },
#   "rate_limits": {
#     "free_tier": "200 requests per 5 hours per IP",
#     "paid_tier": "No gateway-enforced limits"
#   }
# }
```

### Monitoring Workflow

```bash
# Quick check before starting work
kilo-status --balance
# If credits low: add more at https://app.kilo.ai/dashboard

# After a long session, check usage
kilo-status --usage
# Shows tokens consumed and estimated cost

# Set up periodic monitoring (cron)
# */30 * * * * kilo-status --json >> ~/kilo-usage.log
```

---

## Advanced Usage

### Dry-Run Mode

Preview any switch action without executing:

```bash
DRY_RUN=1 kilo-env work kilo          # See what would run
DRY_RUN=1 kilo-profile switch work    # See what files would be copied
```

### Security Features

| Feature | How It Works |
|---------|-------------|
| Hash-based detection | Compares SHA256 hashes — never shows API key characters |
| Key masking | `sk-a****xyz (48 chars)` — reads from file, not env |
| JSON validation | Blocks switch if config has invalid JSON |
| Auth backup | Timestamped backups before overwriting `auth.json` |
| File permissions | All credential files created with `chmod 600` |

### Shell Integration

Add to `~/.zshrc` or `~/.bashrc`:

```bash
# Quick aliases
alias ke='kilo-env'
alias kp='kilo-profile'
alias kw='kilo-env work kilo'
alias kp-work='kilo-profile switch work'
alias kp-personal='kilo-profile switch personal'
alias kl='kilo-env list'
```

### Project-Level Override

Place `opencode.json` in any project root for automatic per-project config:

```jsonc
// ~/projects/client-a/opencode.json
{
  "$schema": "https://app.kilo.ai/config.json",
  "model": "anthropic/claude-sonnet-4",
  "provider": {
    "anthropic": {
      "options": { "apiKey": "{env:ANTHROPIC_API_KEY}" }
    }
  }
}
```

This overrides both global config and active profile when you `cd` into the project.

### Troubleshooting

**"Account not found"**
```bash
kilo-env list                    # Check available accounts
ls -la ~/.config/kilo/accounts/  # Verify directory contents
```

**"Config not loading"**
```bash
kilo-env validate work           # Check syntax
cat ~/.config/kilo/opencode.json | python3 -m json.tool  # Validate JSON
```

**"Auth token expired"**
```bash
kilo login                       # Re-authenticate
kilo-profile create work         # Save new auth to profile
```

## Productivity Workflows

### Full Stack Pipeline

Combine Kilo with other tools for maximum productivity:

```bash
# Health check all tools
ai-health.sh

# Run parallel task across Kilo, OpenCode, and Codex
ai-orchestrator.sh run --tools kilo,opencode,codex "implement authentication"

# Analyze costs
cost-analyzer.sh --daily

# Auto-generate commit
git-ai.sh commit "add login feature"
```

### Multi-Tool Parallel Execution

For large tasks, use Kilo as the orchestrator:
```bash
# Schema → Kilo (best for DB design)
# API → OpenCode (best for backend)
# Tests → Qwen (best for test generation)
# Frontend → Gemini (best for UI)
```

This pattern delivers 3-5x faster delivery than using a single tool.
