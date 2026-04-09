# OpenCode Multi-Account Management Scripts

Scripts for managing multiple OpenCode CLI accounts — environment-based switching and full config profile rotation.

## Quick Start

### Option 1: Environment-Based (Recommended)

**Best for:** Multi-provider setups where each account has different API keys.

```bash
# Install
sudo cp scripts/opencode-env.sh /usr/local/bin/opencode-env
sudo chmod +x /usr/local/bin/opencode-env

# Create accounts
opencode-env create work
opencode-env create personal

# Edit and add your API keys
opencode-env edit work
opencode-env edit personal

# Use
opencode-env work                     # Export vars to shell
opencode                              # Run with work credentials

# Or one-shot
opencode-env work opencode            # Run opencode with work account
opencode-env personal opencode        # Run with personal account
```

### Option 2: Full Profile Rotation

**Best for:** Complete isolation — different providers, models, permissions, and mode configs.

```bash
# Install
sudo cp scripts/opencode-profile.sh /usr/local/bin/opencode-profile
sudo chmod +x /usr/local/bin/opencode-profile

# Set up default config first, then create profiles
opencode-profile create work
opencode-profile create personal

# Edit each profile
opencode-profile edit work
opencode-profile edit personal

# Switch
opencode-profile switch work
opencode                              # Run with work profile
```

---

## Scripts Overview

### `opencode-env.sh`

Manages accounts via environment variable files. Each account stores credentials for **multiple providers** (Anthropic, OpenAI, Gemini, Bedrock, Azure, etc.).

**Commands:**

| Command | Description |
|---------|-------------|
| `opencode-env list` | List all accounts with provider/model info |
| `opencode-env create <name>` | Create new account with `.env` template |
| `opencode-env show <name>` | Show config (keys masked, hash-based active detection) |
| `opencode-env edit <name>` | Edit in `$EDITOR` with post-save validation |
| `opencode-env validate <name>` | Validate env file syntax |
| `opencode-env <name>` | Export vars to current shell |
| `opencode-env <name> opencode` | Run opencode with account credentials |

**Directory Structure:**
```
~/.config/opencode/accounts/
├── work.env
├── personal.env
├── bedrock.env
└── client-a.env
```

**Account File Format (`.env`):**
```bash
# Provider API Keys
ANTHROPIC_API_KEY=sk-ant-...
OPENAI_API_KEY=sk-proj-...

# Routing
OPENCODE_DEFAULT_PROVIDER=anthropic
OPENCODE_DEFAULT_MODEL=claude-sonnet-4-20250514

# Optional: full config override
# OPENCODE_CONFIG_CONTENT='{"model":"anthropic/claude-sonnet-4"}'
```

---

### `opencode-profile.sh`

Manages complete OpenCode configurations including providers, models, permissions, and mode-based agent routing. Each profile is an isolated directory.

**Commands:**

| Command | Description |
|---------|-------------|
| `opencode-profile list` | List profiles with model/providers/modes |
| `opencode-profile create <name>` | Create from current config |
| `opencode-profile switch <name>` | Switch (with JSON validation) |
| `opencode-profile delete <name>` | Delete (with confirmation) |
| `opencode-profile current` | Show active profile |
| `opencode-profile edit <name>` | Edit config in `$EDITOR` |
| `opencode-profile validate <name>` | Validate JSON syntax |

**Directory Structure:**
```
~/.config/opencode/
├── opencode.json              # Active config (swapped by profiles)
├── .active_profile            # Tracks current profile
└── profiles/
    ├── work/
    │   ├── opencode.json      # Full work config
    │   └── auth.json          # Work auth tokens
    └── personal/
        ├── opencode.json      # Personal config
        └── auth.json          # Personal auth
```

---

## Security Features

| Feature | Description |
|---------|-------------|
| **Hash-based active detection** | Compares SHA256 hashes — never exposes API key prefixes |
| **Key masking** | Shows `sk-a****xyz (48 chars)` — reads from file, not current env |
| **JSON validation** | Blocks switch if config has invalid JSON |
| **Auth backup** | Timestamped backups before overwriting `auth.json` |
| **File permissions** | All credential files created with `chmod 600` |
| **Dry-run mode** | `DRY_RUN=1` previews all actions without executing |

---

## Supported Providers

| Provider | Env Var | Example |
|----------|---------|---------|
| Anthropic | `ANTHROPIC_API_KEY` | `sk-ant-...` |
| OpenAI | `OPENAI_API_KEY` | `sk-proj-...` |
| Google Gemini | `GEMINI_API_KEY` | `ai-...` |
| Groq | `GROQ_API_KEY` | `gsk-...` |
| OpenRouter | `OPENROUTER_API_KEY` | `sk-or-...` |
| xAI (Grok) | `XAI_API_KEY` | `xai-...` |
| Azure OpenAI | `AZURE_OPENAI_ENDPOINT` + `AZURE_OPENAI_API_KEY` | — |
| AWS Bedrock | `AWS_ACCESS_KEY_ID` + `AWS_SECRET_ACCESS_KEY` + `AWS_REGION` | — |
| GitHub Copilot | `GITHUB_TOKEN` | `ghp_...` |

---

## Shell Integration

Add to `~/.bashrc` or `~/.zshrc`:

```bash
# Quick aliases for opencode-env
alias oc-work='opencode-env work opencode'
alias oc-personal='opencode-env personal opencode'
alias oc-list='opencode-env list'

# Quick aliases for opencode-profile
alias ocp-work='opencode-profile switch work'
alias ocp-personal='opencode-profile switch personal'
alias ocp-list='opencode-profile list'

# Auto-complete (bash)
_opencode_env_complete() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    local accounts=$(ls ~/.config/opencode/accounts/*.env 2>/dev/null | xargs -n1 basename | sed 's/\.env$//')
    COMPREPLY=($(compgen -W "$accounts list create show edit validate" -- "$cur"))
}
complete -F _opencode_env_complete opencode-env
```

---

## Best Practices

### 1. Use `{env:...}` in config files
```jsonc
{
  "provider": {
    "anthropic": {
      "options": { "apiKey": "{env:ANTHROPIC_API_KEY}" }
    }
  }
}
```

### 2. Secure credential files
```bash
chmod 600 ~/.config/opencode/accounts/*.env
chmod 600 ~/.local/share/opencode/auth.json
```

### 3. Use `.gitignore`
```
.opencode.json
opencode.json
accounts/*.env
!.opencode.json.example
```

### 4. Project-level configs override profiles
Place `.opencode.json` in project root for per-project overrides that persist regardless of active profile.

---

## OpenCode-Specific Notes

### Multi-Provider Architecture
Unlike Kilo CLI (single active provider), OpenCode defines **all providers in one config** and routes via `model: "provider-id/model-name"`. Account files reflect this by storing multiple provider keys simultaneously.

### `OPENCODE_CONFIG_CONTENT`
This environment variable injects a **complete JSON config** — highest non-managed priority. Use it in account files when you need per-account config injection:
```bash
OPENCODE_CONFIG_CONTENT='{"model":"anthropic/claude-sonnet-4","provider":{"anthropic":{"options":{}}}}'
```

### Mode-Based Agent Routing
OpenCode supports per-mode model routing:
```jsonc
{
  "mode": {
    "build": { "model": "anthropic/claude-sonnet-4" },
    "plan":  { "model": "openai/gpt-4o-mini" }
  }
}
```
Profiles store complete `opencode.json` files with mode configs — switching profiles swaps the entire agent routing setup.

---

## Examples

See `examples/opencode-accounts/` for templates:
- `work.env.example` — Multi-provider work account
- `personal.env.example` — Single-provider personal account
- `bedrock.env.example` — AWS Bedrock credentials
- `work-opencode.json.example` — Full work profile with modes
- `personal-opencode.json.example` — Minimal personal profile
