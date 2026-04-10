# Claude Code CLI — Multi-Account User Guide

## Overview

Claude Code CLI uses `CLAUDE_CONFIG_DIR` to point at a complete `~/.claude/` configuration directory. Each directory is fully self-contained with settings, credentials, commands, skills, agents, and session history.

**Config locations:**
- Default: `~/.claude/`
- Override: `CLAUDE_CONFIG_DIR=/custom/path`
- Auth: `~/.claude.json` (OAuth tokens, runtime state)
- Enterprise: `/etc/claude-code/managed-settings.json` (cannot be overridden)

**Config hierarchy (highest to lowest):**
1. Enterprise managed settings (read-only)
2. CLI flags
3. Local project: `.claude/settings.local.json`
4. Shared project: `.claude/settings.json`
5. User: `~/.claude/settings.json` (respects `CLAUDE_CONFIG_DIR`)
6. Environment variables

**Key environment variables:**
| Variable | Purpose |
|----------|---------|
| `CLAUDE_CONFIG_DIR` | Override the entire `~/.claude/` directory |
| `ANTHROPIC_API_KEY` | Direct API key (bypasses OAuth) |
| `ANTHROPIC_MODEL` | Override model (e.g., `claude-sonnet-4-20250514`) |
| `CLAUDE_CODE_USE_BEDROCK=1` | Use AWS Bedrock instead of direct API |
| `AWS_ACCESS_KEY_ID` | AWS Bedrock credentials |
| `AWS_SECRET_ACCESS_KEY` | AWS Bedrock secret key |
| `AWS_REGION` | AWS region |
| `CLAUDE_CODE_USE_VERTEX=1` | Use Google Vertex AI |
| `GOOGLE_CLOUD_PROJECT` | GCP project for Vertex AI |
| `CLAUDE_CODE_USE_FOUNDRY=1` | Use Microsoft Foundry |
| `CLAUDE_CODE_SUBAGENT_MODEL` | Override subagent model |
| `ANTHROPIC_LOG=debug` | Full API request logging |

---

## Script 1: `claude-env.sh` — Environment-Based Switching

**Best for:** Switching between API key accounts or cloud provider configurations (Bedrock, Vertex AI, Foundry).

### Installation

```bash
sudo cp /path/to/scripts/claude/claude-env.sh /usr/local/bin/claude-env
sudo chmod +x /usr/local/bin/claude-env
# Or alias in ~/.zshrc
alias ce='bash /path/to/scripts/claude/claude-env.sh'
```

### Commands

| Command | Description |
|---------|-------------|
| `claude-env list` | List all accounts with provider/mode info |
| `claude-env create <name>` | Create new account with `.env` template |
| `claude-env show <name>` | Show account config (keys masked) |
| `claude-env edit <name>` | Open account file in `$EDITOR` |
| `claude-env validate <name>` | Check env file + linked `settings.json` |
| `claude-env <name>` | Export vars to current shell |
| `claude-env <name> claude` | Run claude with that account's credentials |

### Quick Start

```bash
# 1. Create accounts
claude-env create work
claude-env create bedrock

# 2. Edit and add credentials
claude-env edit work

# Example work account (~/.config/claude/accounts/work.env):
#   ANTHROPIC_API_KEY=sk-ant-work-key
#   ANTHROPIC_MODEL=claude-sonnet-4-20250514

# Example Bedrock account (~/.config/claude/accounts/bedrock.env):
#   CLAUDE_CODE_USE_BEDROCK=1
#   AWS_ACCESS_KEY_ID=AKIA...
#   AWS_SECRET_ACCESS_KEY=...
#   AWS_REGION=us-east-1

# 3. Use accounts
claude-env work           # Export vars to current shell
claude                    # Start Claude Code with work credentials

# Or one-shot
claude-env work claude                    # Run with work account
claude-env bedrock claude                 # Run with AWS Bedrock account
```

### Cloud Provider Modes

The script detects and displays which provider mode each account uses:

```bash
claude-env list
# Output:
# Available accounts:
#
#   • work ✓  (anthropic/claude-sonnet-4-20250514)
#   • bedrock  (bedrock/us-east-1)
#   • vertex  (vertex/my-gcp-project)
#   • foundry  (foundry)
```

---

## Script 2: `claude-profile.sh` — Full `CLAUDE_CONFIG_DIR` Rotation

**Best for:** Complete isolation — different settings, tool permissions, custom commands, skills, agents, and session history.

### Installation

```bash
sudo cp /path/to/scripts/claude/claude-profile.sh /usr/local/bin/claude-profile
sudo chmod +x /usr/local/bin/claude-profile
```

### Commands

| Command | Description |
|---------|-------------|
| `claude-profile list` | List profiles with provider/model/commands/skills/agents |
| `claude-profile create <name>` | Create profile from current `~/.claude/` |
| `claude-profile switch <name>` | Activate profile (sets `CLAUDE_CONFIG_DIR`) |
| `claude-profile delete <name>` | Delete a profile |
| `claude-profile current` | Show active profile |
| `claude-profile edit <name>` | Edit `settings.json` in `$EDITOR` |
| `claude-profile validate <name>` | Validate all JSON files in profile |

### Profile Structure

Each profile is a complete `~/.claude/` directory:

```
~/.claude-profiles/
└── work/
    ├── CLAUDE.md              # Global instructions (applied to all sessions)
    ├── settings.json          # Tool permissions & env vars
    ├── settings.local.json    # Personal overrides (gitignored)
    ├── .mcp.json              # MCP server configurations
    ├── commands/              # Custom slash commands
    ├── skills/                # Auto-invoked workflows (SKILL.md + files)
    ├── agents/                # Specialized subagent personas
    ├── hooks/                 # Event-driven automation
    └── projects/              # Session history (excluded from copy)
```

### Activation Methods

**Method 1: Source the activation script** (recommended for current shell)
```bash
claude-profile switch work
# Profile is now active in this shell
claude
```

**Method 2: Direct env override** (for one-shot or scripts)
```bash
CLAUDE_CONFIG_DIR=~/.claude-profiles/work claude
```

**Method 3: New shell**
```bash
source ~/.claude-active-profile
claude
```

### Quick Start

```bash
# 1. Set up default config
claude                         # Configure with primary account

# 2. Create profiles (copies entire ~/.claude/ directory)
claude-profile create work
claude-profile create personal

# 3. Edit each profile
claude-profile edit work       # Modify settings.json, tool permissions
# Edit CLAUDE.md for custom instructions per profile

# 4. Switch profiles
claude-profile switch work
claude                         # Runs with work profile (settings, commands, skills)

# 5. Verify
claude-profile current
# Current profile (from CLAUDE_CONFIG_DIR): work
#   Config dir: /Users/kong/.claude-profiles/work
#   Provider:  anthropic (direct API)
#   Model:     claude-sonnet-4-20250514
```

---

## Advanced Usage

### `.claude/` Directory Explained

| File/Dir | Purpose | Committed to Git? |
|----------|---------|-------------------|
| `CLAUDE.md` | Global instructions | ✅ Yes (team-wide) |
| `CLAUDE.local.md` | Personal overrides | ❌ No (gitignored) |
| `settings.json` | Tool permissions | ✅ Yes (team-wide) |
| `settings.local.json` | Personal permissions | ❌ No (gitignored) |
| `.mcp.json` | MCP server configs | ✅ Yes |
| `commands/` | Custom `/cmd` commands | ✅ Yes |
| `skills/` | Auto-invoked workflows | ✅ Yes |
| `agents/` | Subagent personas | ✅ Yes |
| `hooks/` | Event-driven scripts | ✅ Yes |
| `projects/` | Session history | ❌ No |

### Cloud Provider Comparison

**Direct API** (simplest):
```bash
ANTHROPIC_API_KEY=sk-ant-key
ANTHROPIC_MODEL=claude-sonnet-4-20250514
```

**AWS Bedrock** (enterprise, no Anthropic subscription):
```bash
CLAUDE_CODE_USE_BEDROCK=1
AWS_ACCESS_KEY_ID=AKIA...
AWS_SECRET_ACCESS_KEY=...
AWS_REGION=us-east-1
CLAUDE_CODE_SKIP_BEDROCK_AUTH=1
```

**Google Vertex AI** (GCP integration):
```bash
CLAUDE_CODE_USE_VERTEX=1
GOOGLE_CLOUD_PROJECT=my-project
CLOUD_ML_REGION=us-central1
```

**Microsoft Foundry** (Azure integration):
```bash
CLAUDE_CODE_USE_FOUNDRY=1
# Uses Azure/Entra ID authentication
```

### Dry-Run Mode

```bash
DRY_RUN=1 claude-env work claude        # Preview command
DRY_RUN=1 claude-profile switch work    # Preview CLAUDE_CONFIG_DIR change
```

### Shell Integration

```bash
# ~/.zshrc
alias ce='claude-env'
alias cp='claude-profile'
alias cw='claude-env work claude'
alias cw-bedrock='claude-env bedrock claude'
alias cp-work='claude-profile switch work'
alias cp-personal='claude-profile switch personal'
alias cl='claude-env list'
```

### Troubleshooting

**"Config not changing after switch"**
```bash
echo $CLAUDE_CONFIG_DIR                  # Verify it's set
claude-profile current                   # Check active profile
ls $CLAUDE_CONFIG_DIR/                   # Verify contents
```

**"Bedrock auth failing"**
```bash
claude-env show bedrock                  # Verify AWS vars
aws sts get-caller-identity              # Verify AWS credentials work
```

**"Settings not applying"**
```bash
claude-profile validate work             # Check JSON syntax
cat ~/.claude-profiles/work/settings.json | python3 -m json.tool
```
