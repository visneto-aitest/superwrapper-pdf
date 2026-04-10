# Managing Multiple Accounts for OpenCode CLI

## Overview

OpenCode CLI does **not** have a native "profile switching" feature. It uses a multi-provider architecture where all providers are defined in a single config file, with routing done via `model: "provider-id/model-name"` syntax. Multiple accounts can be managed through environment variable files or full config profile rotation.

### Key Configuration Locations

| Scope | Path | Purpose |
|-------|------|---------|
| Global Config | `~/.opencode.json` or `~/.config/opencode/opencode.json` | Default provider/model settings |
| Global Config (alt) | `~/.config/opencode/.opencode.json` | XDG-style global config |
| Project Config | `.opencode.json` in project root | Per-project overrides (highest priority) |
| Auth Storage | `~/.local/share/opencode/auth.json` | CLI auth tokens (`opencode auth login`) |

### Configuration File Structure

```jsonc
{
  "$schema": "https://opencode.ai/config.json",
  "model": "anthropic/claude-sonnet-4-20250514",
  "small_model": "openai/gpt-4o-mini",
  "provider": {
    "anthropic": {
      "options": { "apiKey": "{env:ANTHROPIC_API_KEY}" }
    },
    "openai": {
      "options": { "apiKey": "{env:OPENAI_API_KEY}" }
    }
  },
  "enabled_providers": ["anthropic", "openai"],
  "disabled_providers": [],
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

### OpenCode's Multi-Provider Architecture

Unlike Kilo CLI (single active provider), OpenCode:
1. **Defines all providers in one config** — each has its own `apiKey`
2. **Routes by model string** — `anthropic/claude-sonnet-4` vs `openai/gpt-4-turbo`
3. **Supports `enabled_providers` / `disabled_providers`** — whitelist/blacklist
4. **Interactive switching** — `ctrl+a` (provider list), `f2` (model switch) during session

### Environment Variables

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
| `AZURE_OPENAI_API_KEY` | Azure OpenAI key |
| `AWS_ACCESS_KEY_ID` | AWS Bedrock access key |
| `AWS_SECRET_ACCESS_KEY` | AWS Bedrock secret key |
| `AWS_REGION` | AWS region |
| `GITHUB_TOKEN` | GitHub Copilot auth |

**Config Priority (highest to lowest):**
1. CLI flags
2. Local config (`.opencode.json` in project root)
3. Environment variables
4. Global config (`~/.config/opencode/opencode.json`)
5. Built-in defaults

---

## Methods for Multiple Account Management

### Method 1: Environment Variable Files (Recommended)

Store multiple provider API keys per account in `.env` files, then source them:

```bash
# Account stores ALL provider keys
ANTHROPIC_API_KEY=sk-ant-work-key
OPENAI_API_KEY=sk-openai-work-key
OPENCODE_DEFAULT_PROVIDER=anthropic
OPENCODE_DEFAULT_MODEL=claude-sonnet-4-20250514
```

### Method 2: Full Config Profile Rotation

Complete isolated directories — each profile has its own `opencode.json` with providers, models, permissions, and mode configs.

### Method 3: Project-Level Override

Place `.opencode.json` in each project root. Takes precedence over global config.

### Method 4: `OPENCODE_CONFIG_CONTENT` Injection

Inject a complete JSON config via environment variable — highest non-managed priority.

### Method 5: Interactive Switching

Use `ctrl+a` to pick provider, `f2` to switch model during an OpenCode session.

---

## Use Cases Overview

| # | Use Case | Best Method | Key Variables |
|---|----------|-------------|---------------|
| 1 | **Personal vs Work** | `opencode-env.sh` | Multiple `*_API_KEY` vars |
| 2 | **AWS Bedrock Profiles** | `opencode-env.sh` | `AWS_*` vars |
| 3 | **Azure OpenAI Environments** | `opencode-env.sh` | `AZURE_OPENAI_*` vars |
| 4 | **Client-Isolated Permissions** | `opencode-profile.sh` | Full `opencode.json` with `mode` configs |
| 5 | **Multi-Provider Strategy** | `opencode-env.sh` | All provider keys + routing vars |
| 6 | **Budget Model Routing** | `opencode-profile.sh` | `small_model` + cheap provider |
| 7 | **Full Config Override** | `opencode-env.sh` | `OPENCODE_CONFIG_CONTENT` |
| 8 | **Team Shared Config** | `opencode-profile.sh` | Shared profile + secrets manager |
| 9 | **Model Evaluation** | Direct env override | Swap `OPENCODE_DEFAULT_MODEL` |
| 10 | **CI/CD Pipeline** | `opencode-env.sh` | CI secrets → env vars |

### Method Selection Guide

| If you need... | Use this method | Why |
|----------------|-----------------|-----|
| Quick account switching | `opencode-env.sh` | Simple, multi-provider support, secure |
| Complete isolation (config + auth + modes) | `opencode-profile.sh` | Separate dirs, full `opencode.json` |
| Per-project auto-switching | Project `.opencode.json` | Commits with repo, automatic |
| Full config injection | `OPENCODE_CONFIG_CONTENT` | Highest priority, no file edits |
| CI/CD integration | Environment variables | Native to all CI platforms |
| Team sharing | Secrets manager + profile template | Centralized credential management |

---

## Account Configuration Examples by Use Case

### Use Case 1: Personal vs Work Accounts

**Work Account** (`~/.config/opencode/accounts/work.env`):
```bash
ANTHROPIC_API_KEY=sk-ant-work-company-key
OPENAI_API_KEY=sk-proj-work-key
OPENCODE_DEFAULT_PROVIDER=anthropic
OPENCODE_DEFAULT_MODEL=claude-sonnet-4-20250514
```

**Personal Account** (`~/.config/opencode/accounts/personal.env`):
```bash
ANTHROPIC_API_KEY=sk-ant-personal-key
OPENCODE_DEFAULT_PROVIDER=anthropic
OPENCODE_DEFAULT_MODEL=claude-sonnet-4-20250514
```

**Switching:**
```bash
opencode-env work
opencode

opencode-env personal
opencode
```

---

### Use Case 2: AWS Bedrock Profiles

**Bedrock Production**:
```bash
AWS_ACCESS_KEY_ID=AKIA-prod-key
AWS_SECRET_ACCESS_KEY=prod-secret
AWS_REGION=us-east-1
OPENCODE_DEFAULT_PROVIDER=bedrock
OPENCODE_DEFAULT_MODEL=anthropic.claude-sonnet-4-20250514-v1:0
```

**Bedrock Staging**:
```bash
AWS_ACCESS_KEY_ID=AKIA-staging-key
AWS_SECRET_ACCESS_KEY=staging-secret
AWS_REGION=us-west-2
OPENCODE_DEFAULT_PROVIDER=bedrock
OPENCODE_DEFAULT_MODEL=anthropic.claude-sonnet-4-20250514-v1:0
```

---

### Use Case 3: Azure OpenAI Environments

**Azure Production**:
```bash
AZURE_OPENAI_ENDPOINT=https://prod-openai.openai.azure.com
AZURE_OPENAI_API_KEY=azure-prod-key
OPENCODE_DEFAULT_PROVIDER=azure
OPENCODE_DEFAULT_MODEL=gpt-4-turbo
```

**Azure Development**:
```bash
AZURE_OPENAI_ENDPOINT=https://dev-openai.openai.azure.com
AZURE_OPENAI_API_KEY=azure-dev-key
OPENCODE_DEFAULT_PROVIDER=azure
OPENCODE_DEFAULT_MODEL=gpt-4o-mini
```

---

### Use Case 4: Client-Isolated Permissions (Profile-Based)

**Client A Profile** (`~/.config/opencode/profiles/client-a/opencode.json`):
```jsonc
{
  "$schema": "https://opencode.ai/config.json",
  "model": "anthropic/claude-sonnet-4-20250514",
  "provider": {
    "anthropic": {
      "options": { "apiKey": "{env:CLIENT_A_ANTHROPIC_KEY}" }
    }
  },
  "mode": {
    "build": {
      "model": "anthropic/claude-sonnet-4-20250514",
      "tools": { "write": false, "edit": false, "bash": false }
    }
  }
}
```

**Client B Profile** (relaxed permissions):
```jsonc
{
  "mode": {
    "build": {
      "tools": { "write": true, "edit": true, "bash": true }
    }
  }
}
```

---

### Use Case 5: Multi-Provider Strategy

**Account with all providers**:
```bash
# All provider keys
ANTHROPIC_API_KEY=sk-ant-key
OPENAI_API_KEY=sk-openai-key
GEMINI_API_KEY=ai-gemini-key
GROQ_API_KEY=gsk-groq-key
OPENROUTER_API_KEY=sk-or-key

# Default routing
OPENCODE_DEFAULT_PROVIDER=anthropic
OPENCODE_DEFAULT_MODEL=claude-sonnet-4-20250514
```

OpenCode will auto-fallback between providers if one is unavailable.

---

### Use Case 6: Budget Model Routing

**Budget Profile** (`~/.config/opencode/profiles/budget/opencode.json`):
```jsonc
{
  "model": "openai/gpt-4o-mini",
  "small_model": "google/gemini-2.0-flash",
  "provider": {
    "openai": { "options": {} },
    "google": { "options": {} }
  }
}
```

**Premium Profile**:
```jsonc
{
  "model": "anthropic/claude-opus-20260224",
  "small_model": "anthropic/claude-sonnet-4-20250514",
  "provider": {
    "anthropic": { "options": {} }
  }
}
```

---

### Use Case 7: Full Config Override via `OPENCODE_CONFIG_CONTENT`

```bash
# In account .env file — inject complete config
OPENCODE_CONFIG_CONTENT='{"model":"anthropic/claude-sonnet-4","provider":{"anthropic":{"options":{}}},"mode":{"build":{"tools":{"write":true}}}}'
```

This bypasses all file-based configs. Useful for:
- Temporary accounts
- CI/CD with fully defined configs
- Testing different permission sets

---

### Use Case 8: Team Shared Config

**Team profile** with 1Password integration:
```bash
#!/usr/bin/env bash
# setup-opencode-team.sh

# Get credentials from 1Password
ANTHROPIC_API_KEY=$(op read "op://Team/OpenCode/ANTHROPIC_API_KEY")
OPENAI_API_KEY=$(op read "op://Team/OpenCode/OPENAI_API_KEY")

# Create account file
mkdir -p ~/.config/opencode/accounts
cat > ~/.config/opencode/accounts/team.env << EOF
ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}
OPENAI_API_KEY=${OPENAI_API_KEY}
OPENCODE_DEFAULT_PROVIDER=anthropic
OPENCODE_DEFAULT_MODEL=claude-sonnet-4-20250514
EOF

chmod 600 ~/.config/opencode/accounts/team.env
echo "✓ Team account configured"
```

---

### Use Case 9: Model Evaluation

```bash
#!/usr/bin/env bash
# Evaluate different providers with the same prompt

PROMPT="Explain the differences between async/await and promises"

echo "=== Provider Evaluation ==="
echo ""

# Anthropic
echo "--- Anthropic Claude Sonnet ---"
ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY \
opencode run --model anthropic/claude-sonnet-4-20250514 "$PROMPT"

echo ""
echo "--- OpenAI GPT-4 Turbo ---"
OPENAI_API_KEY=$OPENAI_API_KEY \
opencode run --model openai/gpt-4-turbo "$PROMPT"

echo ""
echo "--- Google Gemini Flash ---"
GEMINI_API_KEY=$GEMINI_API_KEY \
opencode run --model google/gemini-2.0-flash "$PROMPT"
```

---

### Use Case 10: CI/CD Pipeline

```yaml
# GitHub Actions
- name: Run OpenCode
  env:
    ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
    OPENAI_API_KEY: ${{ secrets.OPENAI_API_KEY }}
  run: |
    opencode run --model anthropic/claude-sonnet-4 "Review and merge PR #123"
```

---

## Best Practices

### 1. Always Use `{env:...}` in Config Files
```jsonc
{
  "provider": {
    "anthropic": {
      "options": { "apiKey": "{env:ANTHROPIC_API_KEY}" }
    }
  }
}
```
Never hardcode API keys in `opencode.json`.

### 2. Secure Credential Files
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

### 4. Project-Level Configs for Auto-Switching
```
project-a/
  └── .opencode.json  # Uses work API keys

project-b/
  └── .opencode.json  # Uses personal API keys
```

### 5. Use `enabled_providers` to Control Active Providers
```jsonc
{
  "enabled_providers": ["anthropic", "openai"],
  "disabled_providers": ["gemini"]
}
```

---

## Useful Commands Reference

| Command | Description |
|---------|-------------|
| `opencode` | Start interactive CLI |
| `opencode auth login` | Authenticate with provider (Google OAuth, etc.) |
| `opencode run --model provider/model "prompt"` | Non-interactive run |
| `opencode run --continue` | Reuse session context |
| `opencode serve` | Start headless server for API access |

### Keyboard Shortcuts (during session)
| Key | Action |
|-----|--------|
| `ctrl+a` | Open provider list |
| `f2` | Switch to recent model |
| `shift+f2` | Switch to previous model |

---

## Summary

| Approach | Complexity | Isolation | Best For |
|----------|-----------|-----------|----------|
| `opencode-env.sh` | Low | Env vars only | Quick switching, multi-provider |
| `opencode-profile.sh` | Medium | Full config + auth | Complete isolation, mode routing |
| Project `.opencode.json` | Low | Per-project | Auto-switching per repo |
| `OPENCODE_CONFIG_CONTENT` | Medium | Full config | CI/CD, temp accounts |
| Interactive (`ctrl+a`) | Low | Session-only | Ad-hoc switching |

**Recommended:** Use `opencode-env.sh` for day-to-day switching and `opencode-profile.sh` when you need complete config isolation (different permissions, mode configs, provider definitions).
