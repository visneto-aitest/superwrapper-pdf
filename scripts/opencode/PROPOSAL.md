# Proposal: OpenCode Multi-Account Management Scripts

## Research Summary: OpenCode Configuration Architecture

### Key Differences from Kilo CLI

| Aspect | Kilo CLI | OpenCode |
|--------|----------|----------|
| **Config Location** | `~/.config/kilo/opencode.json` | `~/.opencode.json` or `~/.config/opencode/opencode.json` |
| **Auth Storage** | `~/.local/share/kilo/auth.json` | `~/.local/share/opencode/auth.json` |
| **Config Format** | JSONC (comments allowed) | JSON or JSONC |
| **Schema** | `https://app.kilo.ai/config.json` | `https://opencode.ai/config.json` |
| **Env Override** | `KILO_PROVIDER`, `KILO_API_KEY` | `OPENCODE_CONFIG`, `OPENCODE_CONFIG_CONTENT` |
| **Provider Routing** | `KILO_PROVIDER` + `KILO_MODEL` | `model: "provider-id/model-name"` |
| **Multi-Provider** | Single active provider | Multiple providers defined simultaneously |
| **Interactive Switch** | `/connect`, `/teams` | `ctrl+a` (provider list), `f2` (model switch) |
| **CLI Commands** | `kilo auth`, `kilo models` | `opencode auth login`, `opencode run --model` |

### OpenCode Provider Configuration Model

OpenCode's architecture is fundamentally different from Kilo's:

1. **Multi-provider by design** — multiple providers are defined in a single config, not switched
2. **Provider routing** is done via `model: "provider-id/model-name"` syntax
3. **`enabled_providers` / `disabled_providers`** — whitelist/blacklist mechanism
4. **Environment variable injection** — `{env:VAR_NAME}` syntax in config
5. **`OPENCODE_CONFIG_CONTENT`** — inject full config via env var (highest non-managed priority)

### Environment Variables

| Variable | Purpose |
|----------|---------|
| `OPENCODE_CONFIG` | Custom config file path |
| `OPENCODE_CONFIG_CONTENT` | Inject inline JSON config (highest priority) |
| `OPENCODE_CONFIG_DIR` | Additional directory for agents/plugins |
| `OPENCODE_PERMISSION` | JSON string to override permissions |
| `OPENCODE_DISABLE_PROJECT_CONFIG` | Block project-level config |
| `ANTHROPIC_API_KEY` | Anthropic provider key |
| `OPENAI_API_KEY` | OpenAI provider key |
| `GEMINI_API_KEY` | Google Gemini key |
| `OPENROUTER_API_KEY` | OpenRouter key |
| `GROQ_API_KEY` | Groq key |
| `XAI_API_KEY` | xAI (Grok) key |
| `AZURE_OPENAI_ENDPOINT` | Azure endpoint |
| `AZURE_OPENAI_API_KEY` | Azure API key |
| `AWS_ACCESS_KEY_ID` | AWS Bedrock access key |
| `AWS_SECRET_ACCESS_KEY` | AWS Bedrock secret key |

### OpenCode Config Structure

```jsonc
{
  "$schema": "https://opencode.ai/config.json",
  "model": "anthropic/claude-sonnet-4-20250514",
  "small_model": "openai/gpt-4o-mini",
  "provider": {
    "anthropic": {
      "options": {
        "apiKey": "{env:ANTHROPIC_API_KEY}"
      }
    },
    "openai": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "OpenAI Custom",
      "options": {
        "apiKey": "{env:OPENAI_API_KEY}",
        "baseURL": "https://api.openai.com/v1"
      },
      "models": {
        "gpt-4-turbo": {
          "name": "GPT-4 Turbo"
        }
      }
    }
  },
  "enabled_providers": ["anthropic", "openai"],
  "disabled_providers": [],
  "mode": {
    "build": {
      "model": "anthropic/claude-sonnet-4",
      "tools": { "write": true, "edit": true, "bash": true }
    },
    "plan": {
      "model": "openai/gpt-4-turbo",
      "tools": { "write": false, "edit": false, "bash": false }
    }
  }
}
```

---

## Proposed Scripts for OpenCode

### Script 1: `opencode-env.sh` — Environment-Based Account Switching

**Capabilities (mirrors `kilo-env.sh`):**

| Command | Description |
|---------|-------------|
| `opencode-env list` | List all account profiles with provider/model info |
| `opencode-env create <name>` | Create new account with `.env` template |
| `opencode-env show <name>` | Show account config (keys masked, hash-based detection) |
| `opencode-env edit <name>` | Edit account in `$EDITOR` |
| `opencode-env validate <name>` | Validate env file syntax |
| `opencode-env <name>` | Export vars to current shell |
| `opencode-env <name> opencode` | Run opencode with account credentials |

**Account `.env` Format:**
```bash
# Provider API keys (one or more)
ANTHROPIC_API_KEY=sk-ant-key-here
OPENAI_API_KEY=sk-openai-key-here
GEMINI_API_KEY=ai-gemini-key-here

# Default model routing
OPENCODE_DEFAULT_PROVIDER=anthropic
OPENCODE_DEFAULT_MODEL=claude-sonnet-4-20250514

# Optional: full config injection
# OPENCODE_CONFIG_CONTENT={"model":"anthropic/claude-sonnet-4"}

# AWS Bedrock (if used)
# AWS_ACCESS_KEY_ID=AKIA...
# AWS_SECRET_ACCESS_KEY=...
# AWS_REGION=us-east-1

# Azure OpenAI (if used)
# AZURE_OPENAI_ENDPOINT=https://your-resource.openai.azure.com
# AZURE_OPENAI_API_KEY=your-azure-key
```

**Key Adaptations for OpenCode:**
- Supports **multiple provider keys** per account (OpenCode's multi-provider model)
- Sets `OPENCODE_CONFIG_CONTENT` for full config override when needed
- Uses `OPENCODE_DEFAULT_PROVIDER` / `OPENCODE_DEFAULT_MODEL` as custom routing vars
- Hash-based active detection (same security fix as kilo)
- JSON validation for any embedded `OPENCODE_CONFIG_CONTENT`

---

### Script 2: `opencode-profile.sh` — Full Config Profile Switching

**Capabilities (mirrors `kilo-profile.sh`):**

| Command | Description |
|---------|-------------|
| `opencode-profile list` | List all profiles with model/provider info |
| `opencode-profile create <name>` | Create profile from current config |
| `opencode-profile switch <name>` | Switch to profile (with JSON validation) |
| `opencode-profile delete <name>` | Delete a profile |
| `opencode-profile current` | Show active profile |
| `opencode-profile edit <name>` | Edit profile config in `$EDITOR` |
| `opencode-profile validate <name>` | Validate profile JSON |
| `DRY_RUN=1 opencode-profile switch <name>` | Preview switch without executing |

**Profile Directory Structure:**
```
~/.config/opencode/profiles/
├── work/
│   ├── opencode.json       # Full work config (providers, models, modes)
│   └── auth.json           # Work auth tokens (if applicable)
├── personal/
│   ├── opencode.json       # Personal config
│   └── auth.json           # Personal auth
└── client-a/
    ├── opencode.json       # Client-specific providers & permissions
    └── auth.json
```

**Key Adaptations for OpenCode:**
- Config file is `opencode.json` (same name as Kilo, but different schema)
- Auth backup from `~/.local/share/opencode/auth.json`
- Validates against `https://opencode.ai/config.json` schema conceptually
- Parses `model` field to show active provider/model in `list` output
- Supports `mode` configurations (build/plan agent routing)

---

## Key Architectural Differences

### Kilo vs OpenCode Account Model

| Aspect | Kilo | OpenCode |
|--------|------|----------|
| **Account Concept** | Single active provider per session | Multiple providers defined, routed by model string |
| **Switching** | Change provider + key | Change entire config OR change env vars |
| **Credentials** | One `KILO_API_KEY` | Multiple `*_API_KEY` vars (one per provider) |
| **Config Injection** | Limited env overrides | `OPENCODE_CONFIG_CONTENT` for full override |
| **Best Strategy** | Env var switching | Per-account env files with multiple keys |

### Implications for Scripts

1. **`opencode-env.sh`** accounts must store **multiple provider keys** (not just one)
2. **`opencode-profile.sh`** profiles contain **complete provider definitions** (not just a single provider override)
3. The `OPENCODE_CONFIG_CONTENT` variable enables powerful per-account config injection that Kilo doesn't have

---

## File Structure

```
opencode/
├── docs/
│   └── opencode-multi-account-management.md
├── scripts/
│   ├── README.md
│   ├── opencode-env.sh          # Environment-based account switching
│   └── opencode-profile.sh      # Full config profile rotation
└── examples/
    └── opencode-accounts/
        ├── work.env.example              # Multi-provider work account
        ├── personal.env.example          # Personal account (Anthropic-only)
        ├── bedrock.env.example           # AWS Bedrock account
        ├── work-opencode.json.example    # Full work profile config
        └── personal-opencode.json.example # Full personal profile config
```

---

## Implementation Plan

### Phase 1: Core Scripts
- [ ] `opencode-env.sh` — based on `kilo-env.sh`, adapted for OpenCode env vars
- [ ] `opencode-profile.sh` — based on `kilo-profile.sh`, adapted for OpenCode config paths

### Phase 2: Security Features
- [ ] Hash-based active account detection (carried over from kilo)
- [ ] Correct key masking for multiple provider keys
- [ ] JSON validation before profile switch
- [ ] Auth backup with timestamps

### Phase 3: Convenience Features
- [ ] `$EDITOR` support
- [ ] `edit` and `validate` commands
- [ ] Dry-run mode
- [ ] Multi-provider key display in `list`/`show`

### Phase 4: Documentation
- [ ] `opencode-multi-account-management.md` — full guide with OpenCode-specific use cases
- [ ] `scripts/README.md` — quick start guide
- [ ] Example `.env` and `.json` templates

### Phase 5: Example Use Cases
- [ ] Work vs Personal (multi-provider)
- [ ] AWS Bedrock account switching
- [ ] Azure OpenAI environments
- [ ] Client-isolated configs with permission profiles
- [ ] Model evaluation across providers

---

## Use Cases Table (Planned)

| # | Use Case | Method | Key Variables |
|---|----------|--------|---------------|
| 1 | **Personal vs Work** | `opencode-env.sh` | Multiple `*_API_KEY` vars |
| 2 | **AWS Bedrock Profiles** | `opencode-env.sh` | `AWS_*` vars + `AWS_PROFILE` |
| 3 | **Azure OpenAI Environments** | `opencode-env.sh` | `AZURE_OPENAI_*` vars |
| 4 | **Client-Isolated Permissions** | `opencode-profile.sh` | Full `opencode.json` with `mode` configs |
| 5 | **Multi-Provider Strategy** | `opencode-env.sh` | All provider keys + `OPENCODE_DEFAULT_PROVIDER` |
| 6 | **Budget Model Routing** | `opencode-profile.sh` | `small_model` + cheap provider |
| 7 | **Full Config Override** | `opencode-env.sh` | `OPENCODE_CONFIG_CONTENT` |
| 8 | **Team Shared Config** | `opencode-profile.sh` | Shared profile + secrets manager |
| 9 | **Model Evaluation** | Direct env override | Swap `OPENCODE_DEFAULT_MODEL` |
| 10 | **CI/CD Pipeline** | `opencode-env.sh` | CI secrets → env vars |

---

## Summary

The proposed scripts will provide the same capabilities as the Kilo scripts but adapted to OpenCode's:
- **Multi-provider architecture** (multiple API keys per account)
- **Different config paths** (`~/.opencode.json` / `~/.config/opencode/opencode.json`)
- **Different auth path** (`~/.local/share/opencode/auth.json`)
- **`OPENCODE_CONFIG_CONTENT`** injection capability
- **`OPENCODE_DEFAULT_PROVIDER` / `OPENCODE_DEFAULT_MODEL`** routing vars
- **`mode`-based agent routing** (build/plan agents)

All security fixes, validation, dry-run, and `$EDITOR` support from the improved Kilo scripts will carry over directly.
