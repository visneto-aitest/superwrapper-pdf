# Managing Multiple Accounts for Kilo AI CLI

## Overview

Kilo AI CLI (built on OpenCode) does **not** have a native "profile switching" feature like AWS CLI. However, multiple accounts can be managed through several strategies:

### Key Configuration Locations

| Scope | Path | Purpose |
|-------|------|---------|
| Global Config | `~/.config/kilo/opencode.json` or `~/.config/kilo/kilo.jsonc` | Default provider/model settings |
| Project Config | `./opencode.json` or `./.opencode/` | Per-project overrides |
| Auth Tokens | `~/.local/share/kilo/auth.json` | CLI session auth (kilo.access token) |
| Plugin Config | `~/.config/kilo/<plugin>/config` | Plugin-specific settings |

### Configuration File Structure

```jsonc
{
  "$schema": "https://app.kilo.ai/config.json",
  "model": "anthropic/claude-sonnet-4-20250514",
  "provider": {
    "anthropic": {
      "options": { "apiKey": "{env:ANTHROPIC_API_KEY}" }
    }
  },
  "permission": { "*": "ask" },
  "mcp": {},
  "instructions": [],
  "disabled_providers": []
}
```

---

## Methods for Multiple Account Management

### Method 1: Environment Variable Switching (Recommended)

The simplest approach - use environment variables to inject different API keys per session.

**Config Setup:**
```jsonc
{
  "provider": {
    "openai": {
      "options": { "apiKey": "{env:OPENAI_API_KEY}" }
    },
    "anthropic": {
      "options": { "apiKey": "{env:ANTHROPIC_API_KEY}" }
    }
  }
}
```

**Session Override:**
```bash
# Override provider at runtime
export KILO_PROVIDER="openai"
export KILO_API_KEY="sk-your-key-here"

# Or for Kilo Gateway
export KILOCODE_MODEL="anthropic/claude-sonnet-4"
export KILO_ORG_ID="your-org-id"
```

---

### Method 2: Multiple Config Files with Shell Scripts

Create separate config directories for each account/profile and switch between them.

---

### Method 3: Project-Level Configuration

Use project-specific `opencode.json` files to isolate accounts per workspace:

```
project-a/
  └── opencode.json  # Uses work API key
  
project-b/
  └── opencode.json  # Uses personal API key
```

---

### Method 4: Organization/Team Switching

For Kilo Gateway accounts with multiple orgs:
- **Interactive:** Run `/teams` or `/org` in the CLI
- **Non-interactive:** Set `KILO_ORG_ID` environment variable

**Priority Order:** `KILO_ORG_ID` (env) > Last `/teams` selection (local auth file)

---

## Shell Scripts for Account Switching

### Script 1: Profile Switcher (Config Directory Rotation)

```bash
#!/usr/bin/env bash
# kilo-profile.sh - Switch between Kilo CLI account profiles

KILO_CONFIG_DIR="$HOME/.config/kilo"
PROFILES_DIR="$KILO_CONFIG_DIR/profiles"

usage() {
    echo "Usage: kilo-profile.sh [list|switch|create|delete|current] [profile-name]"
    echo ""
    echo "Commands:"
    echo "  list                  List all available profiles"
    echo "  switch <profile>      Switch to a profile"
    echo "  create <profile>      Create a new profile from current config"
    echo "  delete <profile>      Delete a profile"
    echo "  current               Show current active profile"
    echo ""
    echo "Examples:"
    echo "  kilo-profile.sh create work"
    echo "  kilo-profile.sh switch personal"
    echo "  KILO_PROFILE=work kilo  # Use with env var"
    exit 1
}

list_profiles() {
    if [ ! -d "$PROFILES_DIR" ]; then
        echo "No profiles found. Create one with: kilo-profile.sh create <name>"
        return
    fi
    
    echo "Available profiles:"
    for profile in "$PROFILES_DIR"/*/; do
        if [ -d "$profile" ]; then
            name=$(basename "$profile")
            marker=""
            if [ -f "$KILO_CONFIG_DIR/.active_profile" ] && \
               [ "$(cat "$KILO_CONFIG_DIR/.active_profile")" = "$name" ]; then
                marker=" (active)"
            fi
            echo "  - $name$marker"
        fi
    done
}

current_profile() {
    if [ -n "$KILO_PROFILE" ]; then
        echo "Current profile (from env): $KILO_PROFILE"
    elif [ -f "$KILO_CONFIG_DIR/.active_profile" ]; then
        echo "Current profile: $(cat "$KILO_CONFIG_DIR/.active_profile")"
    else
        echo "No profile selected. Using default config."
    fi
}

switch_profile() {
    local profile=$1
    
    if [ ! -d "$PROFILES_DIR/$profile" ]; then
        echo "Error: Profile '$profile' not found."
        echo "Create it with: kilo-profile.sh create $profile"
        exit 1
    fi
    
    # Backup current config
    if [ -f "$KILO_CONFIG_DIR/opencode.json" ]; then
        cp "$KILO_CONFIG_DIR/opencode.json" "$KILO_CONFIG_DIR/opencode.json.bak"
    fi
    
    # Restore profile config
    if [ -f "$PROFILES_DIR/$profile/opencode.json" ]; then
        cp "$PROFILES_DIR/$profile/opencode.json" "$KILO_CONFIG_DIR/opencode.json"
    fi
    
    # Copy auth if exists
    if [ -f "$PROFILES_DIR/$profile/auth.json" ]; then
        cp "$PROFILES_DIR/$profile/auth.json" "$HOME/.local/share/kilo/auth.json"
    fi
    
    # Save active profile
    echo "$profile" > "$KILO_CONFIG_DIR/.active_profile"
    
    echo "Switched to profile: $profile"
    echo ""
    echo "Start Kilo with: kilo"
}

create_profile() {
    local profile=$1
    
    if [ -z "$profile" ]; then
        echo "Error: Profile name required."
        exit 1
    fi
    
    # Create profiles directory
    mkdir -p "$PROFILES_DIR/$profile"
    
    # Save current config
    if [ -f "$KILO_CONFIG_DIR/opencode.json" ]; then
        cp "$KILO_CONFIG_DIR/opencode.json" "$PROFILES_DIR/$profile/opencode.json"
    else
        echo "{}" > "$PROFILES_DIR/$profile/opencode.json"
    fi
    
    # Save current auth if exists
    if [ -f "$HOME/.local/share/kilo/auth.json" ]; then
        cp "$HOME/.local/share/kilo/auth.json" "$PROFILES_DIR/$profile/auth.json"
    fi
    
    echo "Created profile: $profile"
    echo "Config saved to: $PROFILES_DIR/$profile/opencode.json"
}

delete_profile() {
    local profile=$1
    
    if [ ! -d "$PROFILES_DIR/$profile" ]; then
        echo "Error: Profile '$profile' not found."
        exit 1
    fi
    
    read -p "Delete profile '$profile'? [y/N] " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        rm -rf "$PROFILES_DIR/$profile"
        
        # Clear active profile if it was the deleted one
        if [ -f "$KILO_CONFIG_DIR/.active_profile" ] && \
           [ "$(cat "$KILO_CONFIG_DIR/.active_profile")" = "$profile" ]; then
            rm "$KILO_CONFIG_DIR/.active_profile"
        fi
        
        echo "Deleted profile: $profile"
    fi
}

# Main command handler
case "${1:-}" in
    list)
        list_profiles
        ;;
    switch)
        if [ -z "${2:-}" ]; then
            echo "Error: Profile name required."
            usage
        fi
        switch_profile "$2"
        ;;
    create)
        create_profile "${2:-}"
        ;;
    delete)
        delete_profile "${2:-}"
        ;;
    current)
        current_profile
        ;;
    *)
        usage
        ;;
esac
```

**Usage:**
```bash
# Make executable
chmod +x kilo-profile.sh
sudo mv kilo-profile.sh /usr/local/bin/kilo-profile

# Create profiles
kilo-profile create work
kilo-profile create personal

# Edit profile configs
nano ~/.config/kilo/profiles/work/opencode.json
nano ~/.config/kilo/profiles/personal/opencode.json

# Switch profiles
kilo-profile switch work
kilo-profile switch personal

# List all profiles
kilo-profile list

# Check current
kilo-profile current
```

---

### Script 2: Environment-Based Account Switcher

```bash
#!/usr/bin/env bash
# kilo-env.sh - Quick environment variable switching for Kilo CLI

# Account definitions
declare -A KILO_ACCOUNTS=(
    ["work"]="openai:sk-work-key-here:your-work-org-id"
    ["personal"]="anthropic:sk-personal-key-here:"
    ["freelance"]="openai:sk-freelance-key-here:"
)

usage() {
    echo "Usage: kilo-env.sh <account-name> [command]"
    echo ""
    echo "Available accounts:"
    for account in "${!KILO_ACCOUNTS[@]}"; do
        echo "  - $account"
    done
    echo ""
    echo "Examples:"
    echo "  kilo-env.sh work                    # Export vars for current shell"
    echo "  kilo-env.sh work kilo               # Run kilo with work account"
    echo "  kilo-env.sh work kilo --verbose     # Run with args"
    exit 1
}

activate_account() {
    local account=$1
    local config="${KILO_ACCOUNTS[$account]}"
    
    if [ -z "$config" ]; then
        echo "Error: Account '$account' not found."
        echo "Available accounts: ${!KILO_ACCOUNTS[*]}"
        exit 1
    fi
    
    IFS=':' read -r provider api_key org_id <<< "$config"
    
    export KILO_PROVIDER="$provider"
    export KILO_API_KEY="$api_key"
    
    if [ -n "$org_id" ]; then
        export KILO_ORG_ID="$org_id"
    fi
    
    echo "✓ Activated account: $account"
    echo "  Provider: $provider"
    echo "  API Key: ${api_key:0:8}..."
    [ -n "$org_id" ] && echo "  Org ID: $org_id"
    echo ""
    echo "Run 'kilo' to start with this account."
}

run_with_account() {
    local account=$1
    shift
    
    local config="${KILO_ACCOUNTS[$account]}"
    
    if [ -z "$config" ]; then
        echo "Error: Account '$account' not found."
        exit 1
    fi
    
    IFS=':' read -r provider api_key org_id <<< "$config"
    
    # Run command with environment variables
    KILO_PROVIDER="$provider" \
    KILO_API_KEY="$api_key" \
    ${org_id:+KILO_ORG_ID="$org_id"} \
    "$@"
}

# Main
case "${1:-}" in
    ""|--help|-h)
        usage
        ;;
    *)
        if [ "${2:-}" = "" ]; then
            activate_account "$1"
        else
            shift
            run_with_account "$@"
        fi
        ;;
esac
```

**Better Version (Using External Config):**

```bash
#!/usr/bin/env bash
# kilo-env.sh - Environment-based account switcher (secure version)

KILO_ACCOUNTS_DIR="${KILO_ACCOUNTS_DIR:-$HOME/.config/kilo/accounts}"

usage() {
    echo "Usage: kilo-env.sh <account-name> [command...]"
    echo ""
    echo "Accounts directory: $KILO_ACCOUNTS_DIR"
    echo ""
    echo "Commands:"
    echo "  list                  List available accounts"
    echo "  create <name>         Create new account config"
    echo "  <name>                Export account env vars"
    echo "  <name> <command>      Run command with account"
    exit 1
}

list_accounts() {
    if [ ! -d "$KILO_ACCOUNTS_DIR" ]; then
        echo "No accounts found. Create one with: kilo-env.sh create <name>"
        return
    fi
    
    echo "Available accounts:"
    for file in "$KILO_ACCOUNTS_DIR"/*.env; do
        if [ -f "$file" ]; then
            name=$(basename "$file" .env)
            echo "  - $name"
        fi
    done
}

create_account() {
    local name=$1
    
    if [ -z "$name" ]; then
        echo "Error: Account name required."
        exit 1
    fi
    
    mkdir -p "$KILO_ACCOUNTS_DIR"
    
    local file="$KILO_ACCOUNTS_DIR/$name.env"
    
    if [ -f "$file" ]; then
        echo "Account '$name' already exists."
        exit 1
    fi
    
    cat > "$file" << 'EOF'
# Kilo CLI Account Configuration
# Fill in your credentials below

KILO_PROVIDER=openai
KILO_API_KEY=sk-your-key-here
# KILO_ORG_ID=your-org-id  # Optional
# KILO_MODEL=gpt-4         # Optional
EOF
    
    echo "Created: $file"
    echo "Edit this file to add your credentials:"
    echo "  nano $file"
    echo ""
    echo "Then activate with: kilo-env.sh $name"
}

load_account() {
    local name=$1
    local file="$KILO_ACCOUNTS_DIR/$name.env"
    
    if [ ! -f "$file" ]; then
        echo "Error: Account '$name' not found at $file"
        exit 1
    fi
    
    # Source the env file (only exported vars)
    set -a
    source "$file"
    set +a
    
    echo "✓ Loaded account: $name"
    echo "  Provider: ${KILO_PROVIDER:-default}"
    echo "  API Key: ${KILO_API_KEY:0:8}..."
    [ -n "$KILO_ORG_ID" ] && echo "  Org ID: $KILO_ORG_ID"
}

run_with_account() {
    local name=$1
    shift
    
    local file="$KILO_ACCOUNTS_DIR/$name.env"
    
    if [ ! -f "$file" ]; then
        echo "Error: Account '$name' not found."
        exit 1
    fi
    
    # Run command with sourced environment
    (
        set -a
        source "$file"
        set +a
        exec "$@"
    )
}

# Main
case "${1:-}" in
    list)
        list_accounts
        ;;
    create)
        create_account "${2:-}"
        ;;
    ""|--help|-h)
        usage
        ;;
    *)
        if [ "${2:-}" = "" ]; then
            load_account "$1"
        else
            shift
            run_with_account "$@"
        fi
        ;;
esac
```

**Usage:**
```bash
chmod +x kilo-env.sh
sudo mv kilo-env.sh /usr/local/bin/kilo-env

# Create account configs
kilo-env create work
kilo-env create personal

# Edit the configs
nano ~/.config/kilo/accounts/work.env
nano ~/.config/kilo/accounts/personal.env

# List accounts
kilo-env list

# Activate in current shell
kilo-env work
kilo  # Runs with work account

# Or run directly
kilo-env personal kilo
kilo-env work kilo --verbose
```

---

### Script 3: Wrapper Function for Shell RC

Add this to your `~/.bashrc` or `~/.zshrc`:

```bash
# Kilo CLI multi-account helper
kilo-use() {
    local account=$1
    local config_file="$HOME/.config/kilo/accounts/$account.jsonc"
    
    if [ -z "$account" ]; then
        echo "Usage: kilo-use <account>"
        echo "Available accounts:"
        ls -1 "$HOME/.config/kilo/accounts/" 2>/dev/null | sed 's/\.jsonc$//' | sed 's/^/  - /'
        return 1
    fi
    
    if [ ! -f "$config_file" ]; then
        echo "Error: Account '$account' not found."
        echo "Create: $config_file"
        return 1
    fi
    
    # Backup and switch config
    cp "$HOME/.config/kilo/opencode.json" "$HOME/.config/kilo/opencode.json.bak" 2>/dev/null
    cp "$config_file" "$HOME/.config/kilo/opencode.json"
    
    echo "✓ Switched to: $account"
    echo "Run 'kilo' to start."
}

# Or use environment variables (cleaner)
kilo-with() {
    local account=$1
    shift
    local env_file="$HOME/.config/kilo/accounts/$account.env"
    
    if [ ! -f "$env_file" ]; then
        echo "Error: Account file not found: $env_file"
        return 1
    fi
    
    # Run with environment
    (
        set -a
        source "$env_file"
        set +a
        exec "$@"
    )
}

# Quick aliases
alias kilo-work='kilo-with work kilo'
alias kilo-personal='kilo-with personal kilo'
alias kilo-list='ls -1 ~/.config/kilo/accounts/ 2>/dev/null | sed "s/\.env$//"'
```

**Usage:**
```bash
# After adding to .zshrc/.bashrc and reloading:
source ~/.zshrc

# Use accounts
kilo-with work kilo
kilo-with personal kilo

# Quick aliases
kilo-work
kilo-personal
kilo-list
```

---

## Account Configuration Examples by Use Case

### Use Cases Overview Table

| # | Use Case | Best For | Method | Key Variables | Example Command |
|---|----------|----------|--------|---------------|-----------------|
| 1 | **Personal vs Work** | Most common scenario | `kilo-env.sh` | `KILO_PROVIDER`, `KILO_API_KEY`, `KILO_ORG_ID` | `kilo-env work kilo` |
| 2 | **Multiple Organizations** | Consultants, client work | direnv + env vars | `KILO_ORG_ID`, `KILOCODE_MODEL` | `cd client-a && kilo` |
| 3 | **Dev vs Production** | Environment isolation | `kilo-env.sh` + CI/CD | `KILO_MODEL` (mini vs opus) | `kilo-env prod kilo` |
| 4 | **Freelancer Multi-Client** | Billing per client | `kilo-env.sh` | `KILO_ORG_ID`, `KILO_API_KEY` | `kilo-env client-acme kilo session list` |
| 5 | **Multi-Provider Strategy** | Task-specific strengths | Wrapper scripts | `KILO_PROVIDER`, `KILO_MODEL` | `kilo-code.sh`, `kilo-write.sh` |
| 6 | **Budget-Conscious** | Cost control | `kilo-env.sh` + monitoring | `KILO_MODEL` (cheap models) | `kilo-budget.sh` |
| 7 | **Agency Multi-Client** | Permission isolation | Project `opencode.json` | `permission` settings | `cd client-a && kilo` |
| 8 | **Regional Data Residency** | GDPR compliance | `kilo-env.sh` | `KILO_BASE_URL`, `KILO_ORG_ID` | `kilo-env eu kilo` |
| 9 | **Open Source vs Commercial** | Free vs paid models | Auto-switch function | `KILO_MODEL`, `KILO_PROVIDER` | `kilo-auto` (pwd-based) |
| 10 | **Testing/Evaluation** | Model comparison | Direct env override | `KILO_PROVIDER`, `KILO_MODEL` | `kilo --non-interactive "$PROMPT"` |
| 11 | **Team Shared Account** | Team onboarding | Secrets manager + `.env` | Shared `KILO_API_KEY` | `setup-kilo-team.sh` |

### Method Selection Guide

| If you need... | Use this method | Why |
|----------------|-----------------|-----|
| Quick account switching | `kilo-env.sh` | Simple, secure, no config files to manage |
| Complete isolation (config + auth) | `kilo-profile.sh` | Separate dirs for each profile |
| Per-project auto-switching | Project `opencode.json` | Commits with repo, automatic |
| Directory-based switching | direnv (`.envrc`) | cd into folder = auto-load |
| Task-based switching | Wrapper scripts (`.sh`) | Explicit, clear intent |
| CI/CD integration | Environment variables | Native to all CI platforms |
| Team sharing | Secrets manager + template | Centralized credential management |

---

### Use Case 1: Personal vs Work Accounts (Most Common)

**Scenario:** Developer needs separate accounts for job and personal projects.

**Work Account** (`~/.config/kilo/accounts/work.env`):
```bash
# Work account - Company OpenAI subscription
KILO_PROVIDER=openai
KILO_API_KEY=sk-proj-work-company-key-here
KILO_ORG_ID=org-company-123456
KILO_MODEL=gpt-4-turbo
```

**Personal Account** (`~/.config/kilo/accounts/personal.env`):
```bash
# Personal account - Individual Anthropic subscription
KILO_PROVIDER=anthropic
KILO_API_KEY=sk-ant-personal-key-here
KILO_MODEL=claude-sonnet-4-20250514
```

**Switching:**
```bash
# Morning - work mode
kilo-env work
cd ~/projects/company-project
kilo

# Evening - personal mode
kilo-env personal
cd ~/personal-side-project
kilo
```

---

### Use Case 2: Multiple Organizations/Teams

**Scenario:** Consultant works with multiple client organizations through Kilo Gateway.

```bash
# Client A - Healthcare startup
KILO_ORG_ID=org-healthcare-abc
KILOCODE_MODEL=anthropic/claude-sonnet-4
KILO_PROVIDER=kilocode

# Client B - Fintech company
KILO_ORG_ID=org-fintech-xyz
KILOCODE_MODEL=openai/gpt-4-turbo
KILO_PROVIDER=kilocode

# Client C - E-commerce platform
KILO_ORG_ID=org-ecommerce-123
KILOCODE_MODEL=google/gemini-2.0-flash
KILO_PROVIDER=kilocode
```

**Project auto-switching with `.envrc`:**
```bash
# ~/projects/client-a/.envrc
export KILO_ORG_ID=org-healthcare-abc
export KILOCODE_MODEL=anthropic/claude-sonnet-4

# ~/projects/client-b/.envrc
export KILO_ORG_ID=org-fintech-xyz
export KILOCODE_MODEL=openai/gpt-4-turbo
```

With [direnv](https://direnv.net/), switching directories auto-loads the right org.

---

### Use Case 3: Development vs Production Environments

**Scenario:** Separate accounts for testing (cheap models) vs production (premium models).

**Development Account** (`~/.config/kilo/accounts/dev.env`):
```bash
# Dev - Use cheaper/faster models for experimentationation
KILO_PROVIDER=openai
KILO_API_KEY=sk-proj-dev-key-here
KILO_MODEL=gpt-4o-mini  # Cheaper, faster for dev work
```

**Production Account** (`~/.config/kilo/accounts/prod.env`):
```bash
# Production - Use best models for critical work
KILO_PROVIDER=anthropic
KILO_API_KEY=sk-ant-prod-key-here
KILO_MODEL=claude-opus-20260224  # Premium model for production
```

**CI/CD Integration:**
```bash
# GitHub Actions - Production deployment
- name: Deploy with Kilo
  env:
    KILO_API_KEY: ${{ secrets.KILO_PROD_API_KEY }}
    KILO_MODEL: claude-opus-20260224
  run: kilo --non-interactive "Review and deploy"
```

---

### Use Case 4: Freelancer with Multiple Clients

**Scenario:** Freelancer manages billing separately per client project.

```
~/.config/kilo/accounts/
├── client-acme.env      # Acme Corp - they pay for usage
├── client-globex.env    # Globex Inc - separate billing
├── client-initech.env   # Initech - their own API keys
└── personal.env         # Your own projects
```

**client-acme.env:**
```bash
# Acme Corp provided API key
KILO_PROVIDER=openai
KILO_API_KEY=sk-proj-acme-provided-key
KILO_MODEL=gpt-4-turbo
# Track usage for this client
KILO_ORG_ID=org-acme-corp
```

**Quick billing check:**
```bash
# Check usage for specific client
kilo-env client-acme kilo session list
```

---

### Use Case 5: Multi-Provider Strategy

**Scenario:** Use different providers for different strengths (OpenAI for code, Anthropic for writing, Google for analysis).

**Global config** (`~/.config/kilo/opencode.json`):
```jsonc
{
  "provider": {
    "openai": {
      "options": { "apiKey": "{env:OPENAI_API_KEY}" }
    },
    "anthropic": {
      "options": { "apiKey": "{env:ANTHROPIC_API_KEY}" }
    },
    "google": {
      "options": { "apiKey": "{env:GOOGLE_API_KEY}" }
    }
  }
}
```

**Task-specific scripts:**
```bash
#!/usr/bin/env bash
# kilo-code.sh - Use OpenAI for coding tasks
export KILO_PROVIDER=openai
export KILO_MODEL=gpt-4-turbo
export KILO_API_KEY=$OPENAI_API_KEY
kilo

#!/usr/bin/env bash
# kilo-write.sh - Use Anthropic for writing tasks
export KILO_PROVIDER=anthropic
export KILO_MODEL=claude-sonnet-4-20250514
export KILO_API_KEY=$ANTHROPIC_API_KEY
kilo

#!/usr/bin/env bash
# kilo-analyze.sh - Use Google for data analysis
export KILO_PROVIDER=google
export KILO_MODEL=gemini-2.0-flash
export KILO_API_KEY=$GOOGLE_API_KEY
kilo
```

**Usage:**
```bash
kilo-code.sh      # Coding session
kilo-write.sh     # Writing documentation
kilo-analyze.sh   # Data analysis
```

---

### Use Case 6: Budget-Conscious Usage

**Scenario:** Student or budget user wants to control spending with rate limits and cheap models.

```bash
# Budget account - minimize costs
KILO_PROVIDER=openai
KILO_API_KEY=sk-proj-budget-key
KILO_MODEL=gpt-4o-mini  # ~$0.15/M input tokens

# Premium account - for important work only
KILO_PROVIDER=anthropic
KILO_API_KEY=sk-ant-premium-key
KILO_MODEL=claude-opus-20260224  # ~$15/M input tokens
```

**Usage monitoring script:**
```bash
#!/usr/bin/env bash
# kilo-budget.sh - Track and limit usage

echo "=== Kilo Usage Report ==="

# Check current session
kilo session list

# Show current model (cost indicator)
echo ""
echo "Current model: ${KILO_MODEL:-not set}"
case "${KILO_MODEL:-}" in
  *mini*|*flash*|*haiku*)
    echo "💰 Budget model active (~$0.15-0.50/M tokens)"
    ;;
  *sonnet*|*turbo*|*pro*)
    echo "💵 Mid-tier model (~$3-10/M tokens)"
    ;;
  *opus*|*o1*|*gemini-2*)
    echo "💸 Premium model (~$10-15/M tokens)"
    ;;
  *)
    echo "❓ Unknown model cost"
    ;;
esac
```

---

### Use Case 7: Agency Managing Multiple Clients

**Scenario:** Agency needs isolated environments with different permissions per client.

**client-a-opencode.json** (Strict permissions):
```jsonc
{
  "$schema": "https://app.kilo.ai/config.json",
  "model": "openai/gpt-4-turbo",
  "provider": {
    "openai": {
      "options": { "apiKey": "{env:CLIENT_A_API_KEY}" }
    }
  },
  "permission": {
    "*": "ask",           // Ask for everything
    "bash": "deny",       // No bash commands
    "edit": "ask",        // Ask before editing
    "read": "allow"       // Allow reading
  },
  "mcp": {
    "servers": {
      "github": { "config": { "github_token": "{env:CLIENT_A_GH_TOKEN}" } }
    }
  },
  "instructions": ["client-a-guidelines.md"]
}
```

**client-b-opencode.json** (Relaxed permissions):
```jsonc
{
  "permission": {
    "*": "allow",         // Auto-approve
    "bash": "allow",      // Allow bash commands
    "edit": "allow"       // Allow edits
  }
}
```

**Switch with project configs:**
```bash
# In client-a project directory
cd ~/agency/client-a/project
kilo  # Uses ./opencode.json with strict permissions

# In client-b project directory
cd ~/agency/client-b/project
kilo  # Uses ./opencode.json with relaxed permissions
```

---

### Use Case 8: Regional Data Residency

**Scenario:** EU data must stay in EU endpoints, US data in US endpoints.

**EU Account** (`~/.config/kilo/accounts/eu.env`):
```bash
# EU region - comply with GDPR
KILO_PROVIDER=openai
KILO_API_KEY=sk-proj-eu-key
KILO_MODEL=gpt-4-turbo
# Some providers support region-specific endpoints
KILO_BASE_URL=https://api.openai.com  # Or EU-specific endpoint if available
```

**US Account** (`~/.config/kilo/accounts/us.env`):
```bash
# US region - standard usage
KILO_PROVIDER=openai
KILO_API_KEY=sk-proj-us-key
KILO_MODEL=gpt-4-turbo
```

---

### Use Case 9: Open Source vs Commercial Projects

**Scenario:** Use free/cheap models for open source, premium for commercial work.

**Open Source Account**:
```bash
# Open source - use free tier or cheap models
KILO_PROVIDER=google
KILO_API_KEY=free-api-key
KILO_MODEL=gemini-2.0-flash  # Free tier available
```

**Commercial Account**:
```bash
# Commercial - use best available
KILO_PROVIDER=anthropic
KILO_API_KEY=sk-ant-commercial-key
KILO_MODEL=claude-opus-20260224
```

**Auto-switch based on directory:**
```bash
# Add to ~/.zshrc
kilo-auto() {
  local pwd=$(pwd)
  if [[ "$pwd" == *"open-source"* ]]; then
    kilo-env opensource kilo
  elif [[ "$pwd" == *"commercial"* ]]; then
    kilo-env commercial kilo
  else
    kilo
  fi
}
```

---

### Use Case 10: Testing/Evaluation

**Scenario:** Evaluate different models/providers before committing to production.

**evaluation.sh:**
```bash
#!/usr/bin/env bash
# Evaluate different models with same prompt

PROMPT="Explain the differences between async/await and promises in JavaScript"

echo "=== Model Evaluation ==="
echo "Prompt: $PROMPT"
echo ""

# Test GPT-4o-mini
echo "--- OpenAI GPT-4o-mini ---"
KILO_PROVIDER=openai \
KILO_MODEL=gpt-4o-mini \
KILO_API_KEY=$OPENAI_API_KEY \
kilo --non-interactive "$PROMPT"

echo ""
echo "--- Anthropic Claude Sonnet ---"
KILO_PROVIDER=anthropic \
KILO_MODEL=claude-sonnet-4 \
KILO_API_KEY=$ANTHROPIC_API_KEY \
kilo --non-interactive "$PROMPT"

echo ""
echo "--- Google Gemini Flash ---"
KILO_PROVIDER=google \
KILO_MODEL=gemini-2.0-flash \
KILO_API_KEY=$GOOGLE_API_KEY \
kilo --non-interactive "$PROMPT"
```

---

### Use Case 11: Team Shared Account

**Scenario:** Team shares a single account with common config.

**Team config** (`~/.config/kilo/accounts/team.env`):
```bash
# Team account - shared across developers
KILO_PROVIDER=openai
KILO_API_KEY=sk-proj-team-shared-key
KILO_ORG_ID=org-team-123
KILO_MODEL=gpt-4-turbo
```

**Distribute via team secrets manager:**
```bash
# Team onboarding script
#!/usr/bin/env bash
# setup-kilo-team.sh

echo "Setting up Kilo CLI for team..."

# Get credentials from 1Password/Bitwarden/etc
KILO_API_KEY=$(op read "op://Team/Kilo/API Key")

# Create local config
cat > ~/.config/kilo/accounts/team.env << EOF
KILO_PROVIDER=openai
KILO_API_KEY=${KILO_API_KEY}
KILO_ORG_ID=org-team-123
KILO_MODEL=gpt-4-turbo
EOF

chmod 600 ~/.config/kilo/accounts/team.env

echo "✓ Team Kilo account configured!"
echo "Run: kilo-env team kilo"
```

---

## Best Practices

### 1. **Use Environment Variables for Secrets**
Never hardcode API keys in `opencode.json`. Use `{env:VAR_NAME}` syntax:
```jsonc
{
  "provider": {
    "openai": {
      "options": { "apiKey": "{env:OPENAI_API_KEY}" }
    }
  }
}
```

### 2. **Secure Your Account Files**
```bash
# Restrict permissions on credentials
chmod 600 ~/.config/kilo/accounts/*.env
chmod 600 ~/.local/share/kilo/auth.json
```

### 3. **Use .gitignore**
```bash
# In your project .gitignore
opencode.json
.opencode/
!.opencode.example/
```

### 4. **Combine with Project Config**
```
~/.config/kilo/
├── opencode.json              # Global defaults
├── kilo.jsonc                 # Alternative global config
├── accounts/
│   ├── work.env               # Work credentials
│   ├── personal.env           # Personal credentials
│   └── freelance.env          # Freelance credentials
└── profiles/
    ├── work/
    │   └── opencode.json      # Full work config
    └── personal/
        └── opencode.json      # Full personal config
```

### 5. **Git Hooks for Auto-Switching**
Create `.git/hooks/post-checkout` to auto-switch accounts per branch:
```bash
#!/usr/bin/env bash
# Auto-switch Kilo account based on branch name

BRANCH_NAME=$(git symbolic-ref --short HEAD)
ACCOUNTS_DIR="$HOME/.config/kilo/accounts"

case "$BRANCH_NAME" in
    work-*|feature/*)
        ACCOUNT="work"
        ;;
    personal-*|experiment/*)
        ACCOUNT="personal"
        ;;
    *)
        ACCOUNT="default"
        ;;
esac

if [ -f "$ACCOUNTS_DIR/$ACCOUNT.env" ]; then
    echo "🔄 Switching to '$ACCOUNT' account for branch: $BRANCH_NAME"
    cp "$ACCOUNTS_DIR/$ACCOUNT.env" "$HOME/.config/kilo/active.env"
fi
```

---

## Integration with CI/CD

For automated environments:
```bash
# GitHub Actions
- name: Run Kilo CLI
  env:
    KILO_API_KEY: ${{ secrets.KILO_API_KEY }}
    KILO_PROVIDER: openai
    KILO_ORG_ID: ${{ vars.KILO_ORG_ID }}
  run: kilo --non-interactive
```

---

## Useful Commands Reference

| Command | Purpose |
|---------|---------|
| `kilo` | Start CLI interactively |
| `/connect` | Interactive provider setup |
| `/teams` or `/org` | Switch organizations |
| `/profile`, `/me`, `/whoami` | View current profile |
| `kilo auth` | Manage authentication |
| `kilo models` | List available models |
| `kilo session list` | List sessions |

---

## Environment Variable Reference

| Variable | Purpose | Priority |
|----------|---------|----------|
| `KILO_PROVIDER` | Override provider ID | High |
| `KILO_API_KEY` | Override API key | High |
| `KILO_ORG_ID` | Override organization | Highest |
| `KILO_MODEL` | Override default model | High |
| `KILOCODE_MODEL` | Override Kilo Gateway model | High |
| `KILO_CONFIG_CONTENT` | Inject full config via env | Highest |

---

## Summary

**Recommended Approach:**
1. **Simple:** Use environment variable scripts (`kilo-env.sh`)
2. **Complete:** Use config directory rotation (`kilo-profile.sh`)
3. **Hybrid:** Combine env vars with project-level `opencode.json`

**No native profile switching exists**, but the environment variable system makes it straightforward to build your own switching mechanism.
