# Qwen Code CLI — Multi-Account User Guide

## Overview

Qwen Code CLI uses a native `modelProviders` configuration in `settings.json` with per-model `envKey` mapping for credentials, plus `.env` file loading for API keys. Credentials are **never** stored in `settings.json`.

**Config locations:**
- User settings: `~/.qwen/settings.json` (recommended for `modelProviders`)
- Project settings: Project-level `settings.json` (completely replaces user)
- Key storage: `~/.qwen/.env` or project `.env` files
- OAuth creds: `~/.qwen/oauth_creds.json`

**Key environment variables:**
| Variable | Purpose |
|----------|---------|
| `OPENAI_API_KEY` | OpenAI provider key |
| `ANTHROPIC_API_KEY` | Anthropic provider key |
| `GEMINI_API_KEY` | Google Gemini key |
| `BAILIAN_CODING_PLAN_API_KEY` | Alibaba Cloud Coding Plan key |
| `DASHSCOPE_API_KEY` | DashScope (Tongyi Qianwen) key |
| `QWEN_API_KEY` | Qwen direct key |
| `OPENAI_BASE_URL` | Custom OpenAI-compatible endpoint |
| `QWEN_MODEL` | Default model override |
| `QWEN_REGION` | Region for cloud services |

---

## Script 1: `qwen-env.sh` — Environment-Based Switching

**Best for:** Switching between accounts with different API keys for multiple providers (OpenAI, Anthropic, DashScope, etc.).

### Installation

```bash
sudo cp /path/to/scripts/qwen/qwen-env.sh /usr/local/bin/qwen-env
sudo chmod +x /usr/local/bin/qwen-env
# Or alias in ~/.zshrc
alias qe='bash /path/to/scripts/qwen/qwen-env.sh'
```

### Commands

| Command | Description |
|---------|-------------|
| `qwen-env list` | List all accounts with provider/model info |
| `qwen-env create <name>` | Create new account with `.env` template |
| `qwen-env show <name>` | Show account config (keys masked) |
| `qwen-env edit <name>` | Open account file in `$EDITOR` |
| `qwen-env validate <name>` | Check env file + `~/.qwen/settings.json` |
| `qwen-env <name>` | Export vars to current shell |
| `qwen-env <name> qwen` | Run qwen with that account's credentials |

### Quick Start

```bash
# 1. Create accounts
qwen-env create work
qwen-env create personal

# 2. Edit and add API keys
qwen-env edit work

# Example work account (~/.config/qwen/accounts/work.env):
#   OPENAI_API_KEY=sk-proj-work-key
#   ANTHROPIC_API_KEY=sk-ant-work-key
#   BAILIAN_CODING_PLAN_API_KEY=sk-bailian-key
#   QWEN_MODEL=qwen-coder-plus-latest

# 3. Use accounts
qwen-env work           # Export vars to current shell
qwen                    # Start Qwen Code with work credentials

# Or one-shot
qwen-env work qwen                    # Run with work account
qwen-env personal qwen                # Run with personal account
```

---

## Script 2: `qwen-profile.sh` — Full `~/.qwen/` Rotation

**Best for:** Complete isolation — different `modelProviders` definitions, API keys, and OAuth credentials.

### Installation

```bash
sudo cp /path/to/scripts/qwen/qwen-profile.sh /usr/local/bin/qwen-profile
sudo chmod +x /usr/local/bin/qwen-profile
```

### Commands

| Command | Description |
|---------|-------------|
| `qwen-profile list` | List profiles with providers/region/API keys |
| `qwen-profile create <name>` | Create profile from current config |
| `qwen-profile switch <name>` | Switch to a profile (with JSON validation) |
| `qwen-profile delete <name>` | Delete a profile |
| `qwen-profile current` | Show active profile |
| `qwen-profile edit <name>` | Edit `settings.json` in `$EDITOR` |
| `qwen-profile validate <name>` | Validate all JSON + .env files |

### Profile Structure

```
~/.qwen/profiles/
└── work/
    ├── settings.json       # modelProviders + codingPlan config
    ├── .env                # API keys
    └── oauth_creds.json    # OAuth credentials
```

### `settings.json` Structure

```json
{
  "modelProviders": {
    "openai": [
      {
        "id": "gpt-4-turbo",
        "envKey": "OPENAI_API_KEY",
        "baseUrl": "https://api.openai.com/v1"
      }
    ],
    "anthropic": [
      {
        "id": "claude-sonnet-4-20250514",
        "envKey": "ANTHROPIC_API_KEY"
      }
    ],
    "gemini": [
      {
        "id": "gemini-2.0-flash",
        "envKey": "GEMINI_API_KEY"
      }
    ]
  },
  "codingPlan": {
    "region": "cn-hangzhou"
  }
}
```

Each model entry uses `envKey` to reference a specific environment variable. Credentials are resolved at runtime via `process.env[envKey]`.

### Quick Start

```bash
# 1. Set up default config
qwen                          # Configure with primary account

# 2. Create profiles
qwen-profile create work
qwen-profile create personal

# 3. Edit each profile
qwen-profile edit work        # Modify modelProviders, codingPlan

# 4. Switch profiles
qwen-profile switch work
qwen                          # Runs with work profile

# 5. Verify
qwen-profile current
# Current profile: work
#   Providers: openai/gpt-4-turbo, anthropic/claude-sonnet-4-20250514
#   Region:    cn-hangzhou
```

---

## Advanced Usage

### Multi-Provider Strategy

Qwen Code natively supports multiple providers. Define your full provider catalog in user-level settings, then switch accounts via `.env` files:

```jsonc
// ~/.qwen/settings.json (define once, shared across accounts)
{
  "modelProviders": {
    "openai": [
      { "id": "gpt-4-turbo", "envKey": "OPENAI_API_KEY" }
    ],
    "anthropic": [
      { "id": "claude-sonnet-4-20250514", "envKey": "ANTHROPIC_API_KEY" }
    ],
    "dashscope": [
      { "id": "qwen-coder-plus-latest", "envKey": "DASHSCOPE_API_KEY" }
    ]
  }
}
```

Then each account `.env` file just needs the API keys:

```bash
# ~/.config/qwen/accounts/work.env
OPENAI_API_KEY=sk-proj-work-key
ANTHROPIC_API_KEY=sk-ant-work-key
DASHSCOPE_API_KEY=sk-dashscope-work-key

# ~/.config/qwen/accounts/personal.env
OPENAI_API_KEY=sk-proj-personal-key
DASHSCOPE_API_KEY=sk-dashscope-personal-key
```

### Custom Endpoints

```jsonc
{
  "modelProviders": {
    "openai": [
      {
        "id": "gpt-4-turbo",
        "envKey": "OPENAI_API_KEY",
        "baseUrl": "https://your-custom-proxy/v1"
      }
    ]
  }
}
```

Or via environment variables in the account `.env` file:
```bash
OPENAI_API_KEY=sk-key
OPENAI_BASE_URL=https://your-custom-proxy/v1
```

### Per-Project Provider Override

Place `settings.json` in any project root. **Completely replaces** user-level `modelProviders` (no merging):

```jsonc
// ~/projects/client-a/settings.json
{
  "modelProviders": {
    "dashscope": [
      {
        "id": "qwen-max-latest",
        "envKey": "BAILIAN_CODING_PLAN_API_KEY"
      }
    ]
  },
  "codingPlan": {
    "region": "cn-shanghai"
  }
}
```

### Model Switching

Use the `/model` command during a Qwen Code session to switch providers interactively. Available models come from your `modelProviders` definition.

### Dry-Run Mode

```bash
DRY_RUN=1 qwen-env work qwen            # Preview command
DRY_RUN=1 qwen-profile switch work      # Preview file operations
```

### Shell Integration

```bash
# ~/.zshrc
alias qe='qwen-env'
alias qp='qwen-profile'
alias qw='qwen-env work qwen'
alias qw-personal='qwen-env personal qwen'
alias qp-work='qwen-profile switch work'
alias ql='qwen-env list'
```

### Alibaba Cloud / DashScope Setup

For Chinese users using DashScope or Bailian Coding Plan:

```bash
# ~/.config/qwen/accounts/work.env
BAILIAN_CODING_PLAN_API_KEY=sk-bailian-work-key
QWEN_MODEL=qwen-coder-plus-latest
QWEN_REGION=cn-hangzhou
```

```jsonc
{
  "modelProviders": {
    "dashscope": [
      {
        "id": "qwen-coder-plus-latest",
        "envKey": "BAILIAN_CODING_PLAN_API_KEY"
      }
    ]
  },
  "codingPlan": {
    "region": "cn-hangzhou"
  }
}
```

### Troubleshooting

**"Provider not showing in /model picker"**
```bash
qwen-profile validate work               # Check settings.json syntax
cat ~/.qwen/settings.json | python3 -m json.tool
# Verify modelProviders has no duplicate ids (first entry wins)
```

**"API key not working"**
```bash
qwen-env show work                       # Verify keys are set
echo $OPENAI_API_KEY                     # Check it's exported
```

**"Project config overriding unexpectedly"**
```bash
ls ./*.json settings.json 2>/dev/null    # Check for project-level config
# Project settings.json completely replaces user-level modelProviders
```
