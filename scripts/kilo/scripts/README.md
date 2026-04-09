# Kilo CLI Multi-Account Management Scripts

This directory contains scripts and example configurations for managing multiple Kilo AI CLI accounts.

## Quick Start

### Option 1: Environment-Based Switching (Recommended)

**Best for:** Quick switching between accounts in the same terminal session.

```bash
# 1. Install the script
sudo cp scripts/kilo-env.sh /usr/local/bin/kilo-env
sudo chmod +x /usr/local/bin/kilo-env

# 2. Create account configurations
kilo-env create work
kilo-env create personal

# 3. Edit the configs with your API keys
nano ~/.config/kilo/accounts/work.env
nano ~/.config/kilo/accounts/personal.env

# 4. Use the accounts
kilo-env work          # Export vars to current shell
kilo                   # Start Kilo with work account

# Or run directly
kilo-env work kilo     # Run Kilo with work account
kilo-env personal kilo # Run Kilo with personal account

# List all accounts
kilo-env list
```

### Option 2: Profile-Based Switching

**Best for:** Complete isolation including full config files, permissions, and MCP servers.

```bash
# 1. Install the script
sudo cp scripts/kilo-profile.sh /usr/local/bin/kilo-profile
sudo chmod +x /usr/local/bin/kilo-profile

# 2. Set up your default config first
# Edit ~/.config/kilo/opencode.json with your primary account

# 3. Create profiles
kilo-profile create work
kilo-profile create personal

# 4. Edit each profile's config
nano ~/.config/kilo/profiles/work/opencode.json
nano ~/.config/kilo/profiles/personal/opencode.json

# 5. Switch profiles
kilo-profile switch work
kilo                   # Start Kilo with work profile

# List profiles
kilo-profile list
```

---

## Scripts Overview

### `kilo-env.sh`

Manages multiple accounts using environment variable files.

**Features:**
- ✅ Lightweight - only switches environment variables
- ✅ Secure - credentials in separate `.env` files with 600 permissions
- ✅ Composable - works with any command, not just `kilo`
- ✅ Shell-friendly - can export to current shell or run inline

**Commands:**
```bash
kilo-env list                     # List all accounts
kilo-env create <name>            # Create new account
kilo-env show <name>              # Show account details
kilo-env <name>                   # Export to current shell
kilo-env <name> <command>         # Run command with account
```

**Directory Structure:**
```
~/.config/kilo/accounts/
├── work.env
├── personal.env
└── freelance.env
```

**Account File Format (.env):**
```bash
KILO_PROVIDER=openai
KILO_API_KEY=sk-your-key-here
KILO_ORG_ID=your-org-id  # Optional
KILO_MODEL=gpt-4-turbo   # Optional
```

---

### `kilo-profile.sh`

Manages multiple accounts by rotating complete configuration directories.

**Features:**
- ✅ Complete isolation - configs, auth tokens, permissions
- ✅ Visual switching - clear which profile is active
- ✅ Backup/restore - preserves previous config automatically

**Commands:**
```bash
kilo-profile list                     # List all profiles
kilo-profile create <name>            # Create from current config
kilo-profile switch <name>            # Switch to profile
kilo-profile delete <name>            # Delete a profile
kilo-profile current                  # Show active profile
```

**Directory Structure:**
```
~/.config/kilo/
├── opencode.json              # Active config (swapped by profiles)
├── .active_profile            # Tracks current profile
└── profiles/
    ├── work/
    │   ├── opencode.json      # Work config
    │   └── auth.json          # Work auth tokens
    └── personal/
        ├── opencode.json      # Personal config
        └── auth.json          # Personal auth tokens
```

---

## Shell Integration

Add these to your `~/.bashrc` or `~/.zshrc` for quick access:

```bash
# Source the account switcher
source /path/to/kilo-env.sh

# Quick aliases
alias kilo-work='kilo-env work kilo'
alias kilo-personal='kilo-env personal kilo'
alias kilo-list='kilo-env list'
alias kilo-switch='kilo-env'

# Auto-complete for bash (add to .bashrc)
_kilo_env_complete() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    local accounts=$(ls ~/.config/kilo/accounts/*.env 2>/dev/null | xargs -n1 basename | sed 's/\.env$//')
    COMPREPLY=($(compgen -W "$accounts" -- "$cur"))
}
complete -F _kilo_env_complete kilo-env
```

---

## Example Configurations

See the `examples/kilo-accounts/` directory for:

- `work.env.example` - Work account template
- `personal.env.example` - Personal account template
- `work-opencode.json.example` - Full work config file

---

## Best Practices

### 1. **Never Commit API Keys**
```bash
# Add to .gitignore
echo "*.env" >> .gitignore
echo "accounts/" >> .gitignore

# Secure your files
chmod 600 ~/.config/kilo/accounts/*.env
```

### 2. **Use Environment Variables in Config**
In your `opencode.json`, always use:
```jsonc
{
  "provider": {
    "openai": {
      "options": {
        "apiKey": "{env:KILO_API_KEY}"  // ✅ Good
        // "apiKey": "sk-actual-key"    // ❌ Never do this
      }
    }
  }
}
```

### 3. **Different Accounts Per Project**
Use project-level configs for automatic switching:
```bash
# In each project root
cat > opencode.json << 'EOF'
{
  "model": "openai/gpt-4-turbo",
  "provider": {
    "openai": {
      "options": { "apiKey": "{env:KILO_API_KEY}" }
    }
  }
}
EOF
```

### 4. **Git Hooks for Auto-Switching**

Create `.git/hooks/post-checkout`:
```bash
#!/usr/bin/env bash
# Auto-switch Kilo account based on branch

BRANCH=$(git symbolic-ref --short HEAD)
ACCOUNTS_DIR="$HOME/.config/kilo/accounts"

case "$BRANCH" in
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
    echo "🔄 Kilo account: $ACCOUNT (branch: $BRANCH)"
    cp "$ACCOUNTS_DIR/$ACCOUNT.env" "$HOME/.config/kilo/active.env"
fi
```

Make it executable:
```bash
chmod +x .git/hooks/post-checkout
```

---

## Environment Variables Reference

| Variable | Purpose | Example |
|----------|---------|---------|
| `KILO_PROVIDER` | Override provider ID | `openai`, `anthropic` |
| `KILO_API_KEY` | API key for provider | `sk-your-key` |
| `KILO_ORG_ID` | Organization ID (Gateway) | `org-123456` |
| `KILO_MODEL` | Override default model | `gpt-4-turbo` |
| `KILOCODE_MODEL` | Gateway model override | `anthropic/claude-sonnet-4` |
| `KILO_CONFIG_CONTENT` | Full config via env | JSON string |

**Priority (highest to lowest):**
1. `KILO_CONFIG_CONTENT` (env)
2. `KILO_ORG_ID` (env)
3. `KILO_*` variables (env)
4. Project `opencode.json`
5. Global `~/.config/kilo/opencode.json`

---

## Troubleshooting

### "Account not found"
```bash
# List available accounts
kilo-env list

# Check if directory exists
ls -la ~/.config/kilo/accounts/
```

### "API Key not working"
```bash
# Verify env vars are set
echo $KILO_API_KEY

# Check account file
kilo-env show work
```

### "Config not loading"
```bash
# Verify config syntax
cat ~/.config/kilo/opencode.json | python3 -m json.tool

# Check active profile
kilo-profile current
```

### "Auth token expired"
```bash
# Re-login
kilo login

# Or update auth in profile
kilo-profile switch work
kilo login
kilo-profile create work  # Overwrite with new auth
```

---

## Integration with CI/CD

### GitHub Actions
```yaml
- name: Run Kilo CLI
  env:
    KILO_API_KEY: ${{ secrets.KILO_API_KEY }}
    KILO_PROVIDER: openai
    KILO_ORG_ID: ${{ vars.KILO_ORG_ID }}
  run: |
    npm install -g @kilocode/cli
    kilo --non-interactive
```

### Docker
```dockerfile
ENV KILO_API_KEY=${KILO_API_KEY}
ENV KILO_PROVIDER=openai
ENV KILO_ORG_ID=${KILO_ORG_ID}

RUN npm install -g @kilocode/cli
CMD ["kilo", "--non-interactive"]
```

---

## Kilo CLI Commands Reference

| Command | Description |
|---------|-------------|
| `kilo` | Start interactive CLI |
| `/connect` | Setup/change provider credentials |
| `/teams` or `/org` | Switch organizations |
| `/profile`, `/me` | View current profile |
| `kilo auth` | Manage authentication |
| `kilo models` | List available models |
| `kilo session list` | List active sessions |

---

## Additional Resources

- **Full Documentation:** [docs/kilo-multi-account-management.md](../docs/kilo-multi-account-management.md)
- **Official Kilo CLI Docs:** https://kilo.ai/docs/code-with-ai/platforms/cli
- **Example Configs:** [examples/kilo-accounts/](./examples/kilo-accounts/)

---

## License

These scripts are provided as-is for managing Kilo CLI configurations. Use at your own risk and keep your API keys secure!
