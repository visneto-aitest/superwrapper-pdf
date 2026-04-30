#!/bin/bash

# PI Skills Manager - Combines skills inventory, backup, and restore functionality
# Usage: ./pi_skills_combined.sh [skills|list|backup|restore]

# Function to list Pi skills from various locations
list_pi_skills() {
    echo "=== Pi Coding Agent Skills Inventory ==="
    echo

    # Global skills locations for pi coding agent
    GLOBAL_PATHS=(
        "$HOME/.pi/skills"
        "$HOME/.config/pi/skills"
        "$HOME/.local/share/pi/skills"
        "/usr/local/share/pi/skills"
        "/opt/pi/skills"
        "$HOME/.pi/agent/skills"
        "$HOME/.config/pi/agent/skills"
        "$HOME/.pi/coding/skills"
        "$HOME/.config/pi/coding/skills"
    )

    # Project skills locations (relative to current directory)
    PROJECT_PATHS=(
        "./.pi/skills"
        "./skills"
        "./agent/skills"
        "./pi_skills"
        "./.pi/agent/skills"
        "../.pi/skills"
        "../.pi/agent/skills"
    )

    # Function to list skills in a given path
    list_skills_in_path() {
        local path="$1"
        local context="$2"
        
        if [[ -d "$path" ]]; then
            echo "[$context] Skills in: $path"
            local tmpfile=$(mktemp)
            find "$path" -type f \( -name "SKILL.md" -o -name "skill.yaml" -o -name "skill.yml" -o -name "skill.json" -o -name "*.skill.md" \) -exec dirname {} \; 2>/dev/null | sort -u > "$tmpfile"
            
            if [[ -s "$tmpfile" ]]; then
                while read skill_dir; do
                    local rel_path="${skill_dir#$path/}"
                    [[ -z "$rel_path" ]] && rel_path="root"
                    local skill_name="$rel_path"
                    local desc_file="$skill_dir/SKILL.md"
                    [[ ! -f "$desc_file" ]] && desc_file="$skill_dir/skill.yaml"
                    [[ ! -f "$desc_file" ]] && desc_file="$skill_dir/skill.yml"
                    [[ ! -f "$desc_file" ]] && desc_file="$skill_dir/skill.json"
                    if [[ -f "$desc_file" ]]; then
                        local first_line=$(head -1 "$desc_file" 2>/dev/null | sed 's/^# //')
                        [[ -n "$first_line" ]] && skill_name="$rel_path ($first_line)"
                    fi
                    echo "  - $skill_name"
                done < "$tmpfile"
            else
                local leaf_tmp=$(mktemp)
                find "$path" -type d 2>/dev/null | while read dir; do
                    if [[ -z "$(find "$dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)" ]]; then
                        [[ "$dir" != "$path" ]] && echo "$dir"
                    fi
                done | sort -u > "$leaf_tmp"
                
                if [[ -s "$leaf_tmp" ]]; then
                    while read leaf_dir; do
                        local rel_path="${leaf_dir#$path/}"
                        echo "  - $rel_path"
                    done < "$leaf_tmp"
                else
                    echo "  No skill descriptors or leaf directories found."
                fi
                rm -f "$leaf_tmp"
            fi
            rm -f "$tmpfile"
            echo
        fi
    }

    # Check global paths
    echo "Global Skills:"
    found_global=false
    for gp in "${GLOBAL_PATHS[@]}"; do
        if [[ -d "$gp" ]]; then
            list_skills_in_path "$gp" "Global"
            found_global=true
        fi
    done
    if [[ "$found_global" == false ]]; then
        echo "  No global skills found."
        echo
    fi

    # Check project paths
    echo "Project Skills:"
    found_project=false
    for pp in "${PROJECT_PATHS[@]}"; do
        if [[ -d "$pp" ]]; then
            list_skills_in_path "$pp" "Project"
            found_project=true
        fi
    done
    if [[ "$found_project" == false ]]; then
        echo "  No project skills found."
        echo
    fi

    # Check for pi agent command
    if command -v pi &> /dev/null; then
        echo "Pi Agent Info:"
        pi skills list 2>/dev/null || pi agent skills 2>/dev/null || echo "  Could not retrieve skills via pi command"
        echo
    fi

    # Check for pi config
    if [[ -f "$HOME/.pi/config.json" ]]; then
        echo "Pi Config: $HOME/.pi/config.json"
        echo
    fi

    echo "=== End Pi Coding Agent Skills Inventory ==="
}

# Function to list scripts in the scripts directory
list_scripts() {
    echo "Listing PI skills scripts in scripts directory:"
    ls -la scripts/ | grep -E 'pi_skills|pi\.sh' || echo "No scripts found"
}

# Backup settings to a compressed archive
do_backup() {
    BACKUP_DIR="~/backups"
    mkdir -p "$BACKUP_DIR"
    BACKUP_FILE="$BACKUP_DIR/pi_settings_$(date +%Y%m%d).tar.gz"
    tar -czf "$BACKUP_FILE" -C scripts/ . || echo "Backup failed"
    echo "Settings backed up to: $BACKUP_FILE"
}

# Restore settings from backup
do_restore() {
    if [ ! -d ~/backups ]; then
        echo "No backups found in ~/backups directory"
        return 1
    fi
    BACKUP_FILE="~/backups/pi_settings_*.tar.gz"
    tar -xzf "$BACKUP_FILE" -C scripts/ || echo "Restore failed"
    echo "Settings restored from: $BACKUP_FILE"
}

# Main execution
case "$1" in
    skills)
        list_pi_skills
        exit 0
        ;;
    list)
        list_scripts
        exit 0
        ;;
    backup)
        do_backup
        exit 0
        ;;
    restore)
        do_restore
        exit 0
        ;;
    *)
        echo "Usage: ./pi_skills_combined.sh [skills|list|backup|restore]"
        exit 1
        ;;
esac