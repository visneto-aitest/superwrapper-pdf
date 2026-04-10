# OpenCode CLI — Multi-Account User Guide

## Overview

OpenCode CLI uses a multi-provider architecture where all providers are defined in one config file, with routing done via `model: "provider-id/model-name"`.

**Config locations:**
- Global: `~/.opencode.json` or `~/.config/opencode/opencode.json`
- Project: `./.opencode.json` (highest priority, overrides global)
- Auth: `~/.local/share/opencode/auth.json`

**Key environment variables:**
| Variable | Purpose |
|----------|---------|
| `OPENCODE_CONFIG` | Custom config file path |
| `OPENCODE_CONFIG_CONTENT` | Inject full JSON config (highest non-managed priority) |
| `OPENCODE_CONFIG_DIR` | Additional directory for agents/plugins |
| `OPENCODE_PERMISSION` | JSON string to override permissions |
| `OPENCODE_DISABLE_PROJECT_CONFIG` | Block project-level config |
| `ANTHROPIC_API_KEY` | Anthropic provider key |
| `OPENAI_API_KEY` | OpenAI provider key |
| `GEMINI_API_KEY` | Google Gemini key |
| `GROQ_API_KEY` | Groq key |
| `OPENROUTER_API_KEY` | OpenRouter key |
| `XAI_API_KEY` | xAI (Grok) key |
| `AZURE_OPENAI_ENDPOINT` | Azure OpenAI endpoint |
| `AWS_ACCESS_KEY_ID` | AWS Bedrock credentials |

---

## Script 1: `opencode-env.sh` — Environment-Based Switching

**Best for:** Multi-provider setups where each account has different API keys for multiple providers simultaneously.

### Installation

```bash
sudo cp /path/to/scripts/opencode-env.sh /usr/local/bin/opencode-env
sudo chmod +x /usr/local/bin/opencode-env
# Or alias in ~/.zshrc
alias oe='bash /path/to/scripts/opencode-env.sh'
```

### Commands

| Command | Description |
|---------|-------------|
| `opencode-env list` | List all accounts with provider/model info |
| `opencode-env create <name>` | Create new account with `.env` template |
| `opencode-env show <name>` | Show account config (all keys masked) |
| `opencode-env edit <name>` | Open account file in `$EDITOR` |
| `opencode-env validate <name>` | Check env file + `OPENCODE_CONFIG_CONTENT` JSON |
| `opencode-env <name>` | Export vars to current shell |
| `opencode-env <name> opencode` | Run opencode with that account's credentials |

### Quick Start

```bash
# 1. Create accounts
opencode-env create work
opencode-env create personal

# 2. Edit and add API keys (supports multiple providers per account)
opencode-env edit work

# Example work account (~/.config/opencode/accounts/work.env):
#   # Multiple provider keys
#   ANTHROPIC_API_KEY=sk-ant-work-key
#   OPENAI_API_KEY=sk-proj-work-key
#   OPENCODE_DEFAULT_PROVIDER=anthropic
#   OPENCODE_DEFAULT_MODEL=claude-sonnet-4-20250514

# 3. Use accounts
opencode-env work           # Export vars to current shell
opencode                    # Start OpenCode with work credentials

# Or one-shot
opencode-env work opencode                    # Run with work account
opencode-env personal opencode --model openai/gpt-4-turbo  # Override model
```

### Multi-Provider Account Example

```bash
# ~/.config/opencode/accounts/full-stack.env

# All provider keys
ANTHROPIC_API_KEY=sk-ant-key-here
OPENAI_API_KEY=sk-proj-key-here
GEMINI_API_KEY=ai-key-here
GROQ_API_KEY=gsk-key-here

# Default routing
OPENCODE_DEFAULT_PROVIDER=anthropic
OPENCODE_DEFAULT_MODEL=claude-sonnet-4-20250514

# Optional: Full config override (bypasses file-based config)
# OPENCODE_CONFIG_CONTENT='{"model":"anthropic/claude-sonnet-4","provider":{"anthropic":{"options":{}}}}'
```

---

## Script 2: `opencode-profile.sh` — Full Config Profile Rotation

**Best for:** Complete isolation — different providers, models, permissions, and mode-based agent routing.

### Installation

```bash
sudo cp /path/to/scripts/opencode-profile.sh /usr/local/bin/opencode-profile
sudo chmod +x /usr/local/bin/opencode-profile
```

### Commands

| Command | Description |
|---------|-------------|
| `opencode-profile list` | List profiles with model/providers/modes |
| `opencode-profile create <name>` | Create profile from current config |
| `opencode-profile switch <name>` | Switch to a profile (with JSON validation) |
| `opencode-profile delete <name>` | Delete a profile |
| `opencode-profile current` | Show active profile |
| `opencode-profile edit <name>` | Edit profile config in `$EDITOR` |
| `opencode-profile validate <name>` | Validate profile JSON syntax |

### Profile Structure

```
~/.config/opencode/profiles/
├── work/
│   ├── opencode.json      # Full work config with providers, modes, permissions
│   └── auth.json          # Work auth tokens
└── personal/
    ├── opencode.json      # Personal config
    └── auth.json          # Personal auth
```

### Mode-Based Agent Routing

OpenCode supports per-mode model routing, stored in profiles:

```jsonc
{
  "model": "anthropic/claude-sonnet-4-20250514",
  "mode": {
    "build": {
      "model": "anthropic/claude-sonnet-4-20250514",
      "tools": { "write": true, "edit": true, "bash": true }
    },
    "plan": {
      "model": "openai/gpt-4o-mini",
      "tools": { "write": false, "edit": false, "bash": false }
    }
  }
}
```

Switching profiles swaps the entire agent routing setup.

### Quick Start

```bash
# 1. Set up default config
opencode                         # Configure with primary account

# 2. Create profiles
opencode-profile create work
opencode-profile create personal

# 3. Edit each profile
opencode-profile edit work       # Modify providers, models, modes

# 4. Switch profiles
opencode-profile switch work
opencode                         # Runs with work profile (including mode configs)
```

---

## Advanced Usage

### `OPENCODE_CONFIG_CONTENT` — Full Config Injection

Inject a complete JSON config via environment variable. Highest non-managed priority:

```bash
# In account .env file
OPENCODE_CONFIG_CONTENT='{"model":"anthropic/claude-sonnet-4","provider":{"anthropic":{"options":{}}},"mode":{"build":{"tools":{"write":true}}}}'

# This bypasses all file-based configs for this session
opencode-env ci opencode
```

### Keyboard Shortcuts (during OpenCode session)

| Key | Action |
|-----|--------|
| `ctrl+a` | Open provider list |
| `f2` | Switch to recent model |
| `shift+f2` | Switch to previous model |

### Dry-Run Mode

```bash
DRY_RUN=1 opencode-env work opencode        # Preview command
DRY_RUN=1 opencode-profile switch work      # Preview file operations
```

### Shell Integration

```bash
# ~/.zshrc
alias oe='opencode-env'
alias op='opencode-profile'
alias ow='opencode-env work opencode'
alias op-work='opencode-profile switch work'
alias oe-list='opencode-env list'
```

### Provider Enable/Disable

In your `opencode.json`:

```jsonc
{
  "enabled_providers": ["anthropic", "openai"],
  "disabled_providers": ["gemini"]
}
```

Profiles can have completely different provider sets.

### Project-Level Override

```
project-a/
  └── .opencode.json   # Uses work API keys
project-b/
  └── .opencode.json   # Uses personal API keys
```

Takes precedence over global config and active profile.

### Troubleshooting

**"Invalid JSON in config"**
```bash
opencode-env validate work                # Check .env syntax
cat ~/.config/opencode/opencode.json | python3 -m json.tool  # Validate JSON
```

**"Provider not found"**
```bash
opencode-env show work                    # See which providers are configured
opencode-profile list                     # Check profile details
```

**"Auth not working"**
```bash
opencode auth login                       # Re-authenticate
opencode-profile create work              # Save new auth to profile
```

## Productivity Workflows

OpenCode excels at parallel backend tasks:

```bash
# Run OpenCode in orchestrator mode with other tools
ai-orchestrator.sh run --tools opencode,kilo "build REST API for users"

# Compare OpenCode cost efficiency with other tools
cost-analyzer.sh --compare

# Generate PR from OpenCode changes
git-ai.sh pr --push
```

OpenCode is the most cost-efficient tool for:
- Database schema design
- API endpoint implementation
- Infrastructure as code
- Performance optimization
