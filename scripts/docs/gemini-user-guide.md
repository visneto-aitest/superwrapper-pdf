# Gemini CLI — Multi-Account User Guide

## Overview

Gemini CLI supports two authentication modes:
1. **Google OAuth** (free tier) — Browser-based Google Account login
2. **API Key** (paid/enterprise) — `GEMINI_API_KEY` for higher quotas and enterprise features

Workspace/GCA accounts additionally require `GOOGLE_CLOUD_PROJECT`.

**Config locations:**
- Global: `~/.gemini/settings.json`
- Project: `.gemini/settings.json` (merges with global)
- Global context: `~/.gemini/GEMINI.md` (applied to all sessions)
- Project context: `GEMINI.md` in project root

**Config hierarchy:**
System defaults < Global `~/.gemini/settings.json` < Project `.gemini/settings.json`

**Key environment variables:**
| Variable | Purpose |
|----------|---------|
| `GEMINI_API_KEY` | API key for paid/enterprise tier |
| `GOOGLE_CLOUD_PROJECT` | GCP project (required for Workspace accounts) |
| `GOOGLE_APPLICATION_CREDENTIALS` | Path to service account JSON |
| `GEMINI_MODEL` | Default model override |
| `GEMINI_REGION` | API region |
| `VERTEXAI_PROJECT` | Vertex AI project (alternative to direct Gemini) |
| `VERTEXAI_LOCATION` | Vertex AI location |

---

## Script 1: `gemini-env.sh` — Environment-Based Switching

**Best for:** Switching between API key accounts, Workspace projects, or service accounts.

### Installation

```bash
sudo cp /path/to/scripts/gemini-env.sh /usr/local/bin/gemini-env
sudo chmod +x /usr/local/bin/gemini-env
# Or alias in ~/.zshrc
alias ge='bash /path/to/scripts/gemini-env.sh'
```

### Commands

| Command | Description |
|---------|-------------|
| `gemini-env list` | List all accounts with auth mode/model info |
| `gemini-env create <name>` | Create new account with `.env` template |
| `gemini-env show <name>` | Show account config (keys masked) |
| `gemini-env edit <name>` | Open account file in `$EDITOR` |
| `gemini-env validate <name>` | Check env file + service account JSON |
| `gemini-env <name>` | Export vars to current shell |
| `gemini-env <name> gemini` | Run gemini with that account's credentials |

### Quick Start

```bash
# 1. Create accounts
gemini-env create work
gemini-env create personal

# 2. Edit and add credentials
gemini-env edit work

# Example work account — Workspace mode (~/.config/gemini/accounts/work.env):
#   GOOGLE_CLOUD_PROJECT=my-work-gcp-project
#   GEMINI_MODEL=gemini-2.5-pro

# Example personal account — API key mode (~/.config/gemini/accounts/personal.env):
#   GEMINI_API_KEY=ai-your-personal-key
#   GEMINI_MODEL=gemini-2.5-pro

# 3. Use accounts
gemini-env work           # Export vars to current shell
gemini                    # Start Gemini CLI with work credentials

# Or one-shot
gemini-env work gemini                    # Run with work account
gemini-env personal gemini                # Run with personal account
```

### Auth Mode Detection

The script automatically detects and displays the auth mode:

```bash
gemini-env list
# Output:
# Available accounts:
#
#   • work ✓  (workspace → gemini-2.5-pro (my-work-project))
#   • personal  (api-key → gemini-2.5-pro)
#   • service  (service-account)
#   • free  (oauth)
```

---

## Script 2: `gemini-profile.sh` — Full `~/.gemini/` Rotation

**Best for:** Complete isolation — different settings, global instructions (`GEMINI.md`), and API keys.

### Installation

```bash
sudo cp /path/to/scripts/gemini-profile.sh /usr/local/bin/gemini-profile
sudo chmod +x /usr/local/bin/gemini-profile
```

### Commands

| Command | Description |
|---------|-------------|
| `gemini-profile list` | List profiles with config details |
| `gemini-profile create <name>` | Create profile from current config |
| `gemini-profile switch <name>` | Switch to a profile (with JSON validation) |
| `gemini-profile delete <name>` | Delete a profile |
| `gemini-profile current` | Show active profile |
| `gemini-profile edit <name>` | Edit `settings.json` in `$EDITOR` |
| `gemini-profile validate <name>` | Validate all JSON + .env files |

### Profile Structure

```
~/.gemini/profiles/
└── work/
    ├── settings.json        # Gemini CLI settings (model, theme, etc.)
    ├── .env                 # API keys (if using API key mode)
    └── GEMINI.md            # Global instructions/context
```

### `settings.json` Structure

```json
{
  "model": "gemini-2.5-pro",
  "theme": "default",
  "autoAccept": false,
  "checkpointing": true,
  "generationConfig": {
    "temperature": 0.7,
    "maxOutputTokens": 8192
  }
}
```

### Quick Start

```bash
# 1. Set up default config
gemini                        # Configure with primary account

# 2. Create profiles
gemini-profile create work
gemini-profile create personal

# 3. Edit each profile
gemini-profile edit work      # Modify settings, theme, model

# 4. Switch profiles
gemini-profile switch work
gemini                        # Runs with work profile

# 5. Verify
gemini-profile current
# Current profile: work
#   Config: api-key | model: gemini-2.5-pro | temp: 0.7
```

---

## Advanced Usage

### OAuth (Free Tier) vs API Key (Paid Tier)

**OAuth mode** — No configuration needed. Just run `gemini` and authenticate via browser.

**API Key mode** — Required for:
- Higher rate limits
- Enterprise data protections
- Token caching
- Headless scripting
- CI/CD automation

```bash
# Enable API key mode
export GEMINI_API_KEY="ai-your-key-here"
gemini
```

### Workspace / GCA Accounts

Google Workspace or Google Cloud Access (GCA) accounts require:

```bash
export GOOGLE_CLOUD_PROJECT="your-gcp-project-id"
gemini
```

Without this, login fails with: `"This account requires setting the GOOGLE_CLOUD_PROJECT env var."`

### Service Account Authentication

For automated/CI environments:

```bash
export GOOGLE_APPLICATION_CREDENTIALS="/path/to/service-account.json"
gemini
```

### Vertex AI Mode

Alternative to direct Gemini API — use Vertex AI hosted models:

```bash
export VERTEXAI_PROJECT="your-vertex-project"
export VERTEXAI_LOCATION="us-central1"
gemini
```

### Project-Level Config

Place `.gemini/settings.json` in any project root. Merges with global settings:

```jsonc
// ~/projects/client-a/.gemini/settings.json
{
  "model": "gemini-2.5-pro",
  "autoAccept": true,
  "checkpointing": false
}
```

### Global Instructions

`GEMINI.md` in `~/.gemini/` or project root provides persistent context:

```markdown
# ~/.gemini/GEMINI.md
You are working on a enterprise Java project.
- Follow Google Java Style Guide
- Always add unit tests for new code
- Use Spring Boot 3.x
```

### Custom Slash Commands

Define custom commands in `~/.gemini/commands/` (TOML format):

```toml
# ~/.gemini/commands/review.toml
prompt = "Review the following code for best practices, security issues, and performance."
```

Then use `/review` in any Gemini CLI session.

### Dry-Run Mode

```bash
DRY_RUN=1 gemini-env work gemini          # Preview command
DRY_RUN=1 gemini-profile switch work      # Preview file operations
```

### Shell Integration

```bash
# ~/.zshrc
alias ge='gemini-env'
alias gp='gemini-profile'
alias gw='gemini-env work gemini'
alias gw-personal='gemini-env personal gemini'
alias gp-work='gemini-profile switch work'
alias gl='gemini-env list'
```

### CI/CD Integration

```yaml
# GitHub Actions
- name: Run Gemini CLI
  env:
    GEMINI_API_KEY: ${{ secrets.GEMINI_API_KEY }}
    GOOGLE_CLOUD_PROJECT: ${{ vars.GCP_PROJECT }}
  run: gemini --prompt="Review this code"
```

### Troubleshooting

**"This account requires GOOGLE_CLOUD_PROJECT"**
```bash
gemini-env show work                    # Verify GOOGLE_CLOUD_PROJECT is set
echo $GOOGLE_CLOUD_PROJECT              # Check it's exported
```

**"API key not working"**
```bash
gemini-env show personal                # Verify key is configured
curl -H "x-goog-api-key: $GEMINI_API_KEY" \
  "https://generativelanguage.googleapis.com/v1beta/models"  # Test key
```

**"Settings not applying"**
```bash
gemini-profile validate work            # Check settings.json syntax
cat ~/.gemini/profiles/work/settings.json | python3 -m json.tool
```

**"OAuth stuck in loop"**
```bash
# OAuth mode doesn't use env vars — just run gemini directly
unset GEMINI_API_KEY                    # Remove API key to force OAuth
unset GOOGLE_CLOUD_PROJECT              # Remove GCP project
gemini                                  # Browser auth will open
```
