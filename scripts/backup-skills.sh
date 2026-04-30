#!/bin/bash

# backup-skills.sh - Backup skills/configurations for all agent CLIs
# Creates timestamped backups of skills directories and config files
# Usage: ./backup-skills.sh [backup-dir]

# Disable exit on error for tee-based logging (set -euo pipefail would break tee)
set -eo pipefail

# Configuration
BACKUP_DIR="${1:-$HOME/agent-skills-backup}"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_PATH="$BACKUP_DIR/backup_$TIMESTAMP"
LOG_FILE="$BACKUP_PATH/backup.log"

# Agent definitions - each entry is "agent_name:config_file:skills_dir1:skills_dir2:..."
AGENTS=(
    "kilo:$HOME/.kilo/config.json:$HOME/.kilo/skills:$HOME/.config/kilo/skills:$HOME/.local/share/kilo/skills"
    "pi:$HOME/.pi/config.json:$HOME/.pi/skills:$HOME/.config/pi/skills:$HOME/.local/share/pi/skills"
    "gemini:$HOME/.gemini/config.json:$HOME/.gemini/skills:$HOME/.config/gemini/skills:$HOME/.local/share/gemini/skills"
    "claude:$HOME/.claude/config.json:$HOME/.claude/skills:$HOME/.config/claude/skills:$HOME/.local/share/claude/skills"
    "codex:$HOME/.codex/config.json:$HOME/.codex/skills:$HOME/.config/codex/skills:$HOME/.local/share/codex/skills"
    "opencode:$HOME/.opencode/config.json:$HOME/.opencode/skills:$HOME/.config/opencode/skills:$HOME/.local/share/opencode/skills"
)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_msg() {
    local msg="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${BLUE}[$timestamp]${NC} $msg"
    else
        echo -e "${BLUE}[$timestamp]${NC} $msg" | tee -a "$LOG_FILE"
    fi
}
log_success() {
    local msg="$1"
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${GREEN}✓ $msg${NC}"
    else
        echo -e "${GREEN}✓ $msg${NC}" | tee -a "$LOG_FILE"
    fi
}
log_warn() {
    local msg="$1"
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${YELLOW}⚠ $msg${NC}"
    else
        echo -e "${YELLOW}⚠ $msg${NC}" | tee -a "$LOG_FILE"
    fi
}
log_error() {
    local msg="$1"
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${RED}✗ $msg${NC}"
    else
        echo -e "${RED}✗ $msg${NC}" | tee -a "$LOG_FILE"
    fi
}

log_success() {
    local msg="$1"
    echo -e "${GREEN}✓ $msg${NC}" | tee -a "$LOG_FILE"
}

log_warn() {
    local msg="$1"
    echo -e "${YELLOW}⚠ $msg${NC}" | tee -a "$LOG_FILE"
}

log_error() {
    local msg="$1"
    echo -e "${RED}✗ $msg${NC}" | tee -a "$LOG_FILE"
}

echo "============================================="
echo "  Agent Skills & Config Backup Tool"
echo "============================================="
echo

# Ensure backup directory parent exists
mkdir -p "$BACKUP_DIR" 2>/dev/null || {
    echo "Error: Cannot create backup directory parent: $BACKUP_DIR" >&2
    exit 1
}

# Check for timestamp collision and adjust
if [[ -d "$BACKUP_PATH" ]]; then
    TIMESTAMP=$(date +"%Y%m%d_%H%M%S_%N")
    BACKUP_PATH="$BACKUP_DIR/backup_$TIMESTAMP"
fi

# Detect pre‑backup dry‑run mode (user can pass --dry-run as first argument)
DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    # Shift positional parameters so $1 becomes the actual backup directory if supplied
    shift
    log_msg "Running in DRY‑RUN mode – no files will be copied"
fi

log_msg "Creating backup directory: $BACKUP_PATH"
# Only create the directory when not in dry‑run mode
if [[ "$DRY_RUN" == false ]]; then
    mkdir -p "$BACKUP_PATH"
fi

# Initialize counters
total_agents=0
backed_up_agents=0
total_skills=0
total_configs=0
total_errors=0

# Create manifest file
MANIFEST="$BACKUP_PATH/manifest.txt"
echo "# Agent Skills Backup Manifest" > "$MANIFEST"
echo "# Generated: $(date)" >> "$MANIFEST"
echo "# Timestamp: $TIMESTAMP" >> "$MANIFEST"
echo "" >> "$MANIFEST"

# Process each agent
for agent_entry in "${AGENTS[@]}"; do
    IFS=':' read -ra PARTS <<< "$agent_entry"
    agent_name="${PARTS[0]}"
    config_file="${PARTS[1]}"
    
    total_agents=$((total_agents + 1))
    
    echo
    log_msg "Processing agent: $agent_name"
    
    agent_backup_dir="$BACKUP_PATH/$agent_name"
    mkdir -p "$agent_backup_dir"
    
    agent_has_content=false
    
    # Backup config file if it exists
    if [[ -f "$config_file" ]]; then
        log_msg "Backing up config: $config_file"
        if cp "$config_file" "$agent_backup_dir/config.json" 2>/dev/null; then
            log_success "Config backed up"
            total_configs=$((total_configs + 1))
            agent_has_content=true
        else
            log_error "Failed to backup config: $config_file"
            total_errors=$((total_errors + 1))
        fi
    else
        log_warn "Config not found: $config_file"
    fi
    
    # Backup skills directories
    skills_count=0
    for ((i=2; i<${#PARTS[@]}; i++)); do
        skills_dir="${PARTS[$i]}"
        if [[ -d "$skills_dir" ]]; then
            # Count skill descriptors (actual skills), not empty directories
            skill_descriptors=$(find "$skills_dir" -mindepth 2 -maxdepth 2 -type f \( -name "SKILL.md" -o -name "skill.yaml" -o -name "skill.yml" -o -name "skill.json" \) 2>/dev/null | wc -l)
            if [[ $skill_descriptors -gt 0 ]]; then
                log_msg "Backing up $skill_descriptors skills from: $skills_dir"
                backup_skills_dir="$agent_backup_dir/skills_${i-1}"
                if cp -r "$skills_dir" "$backup_skills_dir" 2>/dev/null; then
                    log_success "$skill_descriptors skills backed up"
                    total_skills=$((total_skills + skill_descriptors))
                    skills_count=$((skills_count + skill_descriptors))
                    agent_has_content=true
                else
                    log_error "Failed to backup skills from: $skills_dir"
                    total_errors=$((total_errors + 1))
                fi
            else
                log_warn "No skill descriptors found in: $skills_dir"
            fi
        fi
    done
    
    # Add to manifest if agent has content
    if [[ "$agent_has_content" == true ]]; then
        backed_up_agents=$((backed_up_agents + 1))
        echo "## $agent_name" >> "$MANIFEST"
        echo "Config: ${config_file##*/}" >> "$MANIFEST"
        echo "Skills: $skills_count" >> "$MANIFEST"
        echo "Backup time: $(date '+%Y-%m-%d %H:%M:%S')" >> "$MANIFEST"
        echo "" >> "$MANIFEST"
    else
        log_warn "No content found for agent: $agent_name"
        rmdir "$agent_backup_dir" 2>/dev/null
    fi
done

# Create restore script
# Use >> to append instead of > to avoid overwriting previous restore scripts if backup dir already exists
RESTORE_SH="$BACKUP_PATH/restore.sh"
# If restore.sh already exists (from a previous run to same BACKUP_DIR), add number suffix
if [[ -f "$RESTORE_SH" ]]; then
    local n=1
    while [[ -f "${BACKUP_PATH}/restore_${n}.sh" ]]; do
        n=$((n + 1))
    done
    RESTORE_SH="${BACKUP_PATH}/restore_${n}.sh"
fi

cat > "$RESTORE_SH" << 'RESTORE_EOF'
#!/bin/bash
# Restore script for agent skills & config backup
# Usage: ./restore.sh [--dry-run]
# Note: Uses nullglob to handle unmatched globs safely

set -euo pipefail

shopt -s nullglob  # Make unmatched globs expand to nothing instead of literal "*"

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    echo "=== DRY RUN MODE - No changes will be made ==="
fi

BACKUP_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "============================================="
echo "  Agent Skills Restore Tool"
echo "============================================="
echo

restore_file() {
    local src="$1"
    local dst="$2"
    local dst_dir=$(dirname "$dst")
    
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would restore: $src -> $dst"
        return 0
    fi
    
    mkdir -p "$dst_dir"
    if cp "$src" "$dst" 2>/dev/null; then
        echo "✓ Restored: $dst"
    else
        echo "✗ Failed: $dst"
        return 1
    fi
}

restore_dir() {
    local src="$1"
    local dst="$2"
    
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would restore directory: $src -> $dst"
        return 0
    fi
    
    mkdir -p "$dst"
    # Copy contents, not the directory itself, to merge with existing
    local item
    for item in "$src"/*; do
        [[ -e "$item" ]] || continue
        if cp -r "$item" "$dst/" 2>/dev/null; then
            echo "✓ Restored: $(basename "$item")"
        else
            echo "✗ Failed: $(basename "$item")"
        fi
    done
}

echo "Restoring from: $BACKUP_DIR"
echo

# Restore each agent
for agent_dir in "$BACKUP_DIR"/*/; do
    [[ ! -d "$agent_dir" ]] && continue
    agent_name=$(basename "$agent_dir")
    [[ "$agent_name" == "backup_"* ]] && continue
    
    echo "Restoring agent: $agent_name"
    
    # Restore config
    if [[ -f "$agent_dir/config.json" ]]; then
        case "$agent_name" in
            kilo) restore_file "$agent_dir/config.json" "$HOME/.kilo/config.json" ;;
            pi)    restore_file "$agent_dir/config.json" "$HOME/.pi/config.json" ;;
            gemini) restore_file "$agent_dir/config.json" "$HOME/.gemini/config.json" ;;
            claude) restore_file "$agent_dir/config.json" "$HOME/.claude/config.json" ;;
            codex) restore_file "$agent_dir/config.json" "$HOME/.codex/config.json" ;;
            opencode) restore_file "$agent_dir/config.json" "$HOME/.opencode/config.json" ;;
        esac
    fi
    
    # Restore skills directories
    for skills_dir in "$agent_dir"/skills_*; do
        [[ ! -d "$skills_dir" ]] && continue
        case "$agent_name" in
            kilo)    restore_dir "$skills_dir" "$HOME/.kilo/skills" ;;
            pi)      restore_dir "$skills_dir" "$HOME/.pi/skills" ;;
            gemini)  restore_dir "$skills_dir" "$HOME/.gemini/skills" ;;
            claude)  restore_dir "$skills_dir" "$HOME/.claude/skills" ;;
            codex)   restore_dir "$skills_dir" "$HOME/.codex/skills" ;;
            opencode) restore_dir "$skills_dir" "$HOME/.opencode/skills" ;;
        esac
    done
    
    echo
done

echo "============================================="
echo "  Restore Complete"
echo "============================================="
RESTORE_EOF

chmod +x "$RESTORE_SH"

# Create summary
SUMMARY_FILE="$BACKUP_PATH/summary.txt"
cat > "$SUMMARY_FILE" << SUMMARY
# Backup Summary
Backup Time: $(date)
Timestamp: $TIMESTAMP
Location: $BACKUP_PATH

Agents Processed: $total_agents
Agents Backed Up: $backed_up_agents
Total Skills: $total_skills
Total Configs: $total_configs
Errors: $total_errors

To restore, run: $BACKUP_PATH/restore.sh
To restore (dry run): $BACKUP_PATH/restore.sh --dry-run
SUMMARY

# Final summary
echo
echo "============================================="
echo "           Backup Complete!"
echo "============================================="
log_success "Backup location: $BACKUP_PATH"
echo
log_msg "Summary:"
echo "  Agents processed: $total_agents"
log_msg "  Agents backed up: $backed_up_agents"
log_msg "  Total skills: $total_skills"
log_msg "  Total configs: $total_configs"
if [[ $total_errors -gt 0 ]]; then
    log_error "Total errors: $total_errors"
fi
echo
log_msg "To restore, run: $BACKUP_PATH/restore.sh"
log_msg "Summary saved to: $SUMMARY_FILE"
echo "============================================="

echo "$BACKUP_PATH"
