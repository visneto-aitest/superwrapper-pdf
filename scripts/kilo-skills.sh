#!/bin/bash

# Kilo.ai Agent Skills Manager - Combines skills inventory, backup, and restore functionality
# Usage: ./kilo-skills.sh [skills|list|backup|restore]

list_kilo_skills() {
    echo "=== Kilo.ai Agent Skills Inventory ==="
    echo

    GLOBAL_PATHS=(
        "$HOME/.kilo/skills"
        "$HOME/.config/kilo/skills"
        "$HOME/.local/share/kilo/skills"
        "/usr/local/share/kilo/skills"
        "/opt/kilo/skills"
        "$HOME/.kilo/agent/skills"
        "$HOME/.config/kilo/agent/skills"
        "$HOME/.kilo/coding/skills"
        "$HOME/.config/kilo/coding/skills"
    )

    PROJECT_PATHS=(
        "./.kilo/skills"
        "./kilo_skills"
        "./skills"
        "./agent/skills"
        "./.kilo/agent/skills"
        "../.kilo/skills"
        "../.kilo/agent/skills"
    )

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

    if command -v kilo &> /dev/null; then
        echo "Kilo Agent Info:"
        kilo skills list 2>/dev/null || kilo agent skills 2>/dev/null || echo "  Could not retrieve skills via kilo command"
        echo
    fi

    if [[ -f "$HOME/.kilo/config.json" ]]; then
        echo "Kilo Config: $HOME/.kilo/config.json"
        echo
    fi

    echo "=== End Kilo.ai Agent Skills Inventory ==="
}

list_scripts() {
    echo "Listing Kilo.ai scripts in scripts directory:"
    ls -la scripts/ | grep -E 'kilo' || echo "No scripts found"
}

do_backup() {
    BACKUP_DIR="~/backups"
    mkdir -p "$BACKUP_DIR"
    BACKUP_FILE="$BACKUP_DIR/pi_settings_$(date +%Y%m%d).tar.gz"
    tar -czf "$BACKUP_FILE" -C scripts/ . || echo "Backup failed"
    echo "Settings backed up to: $BACKUP_FILE"
}

do_restore() {
    if [ ! -d ~/backups ]; then
        echo "No backups found in ~/backups directory"
        return 1
    fi
    BACKUP_FILE="~/backups/pi_settings_*.tar.gz"
    tar -xzf "$BACKUP_FILE" -C scripts/ || echo "Restore failed"
    echo "Settings restored from: $BACKUP_FILE"
}

case "$1" in
    skills)
        list_kilo_skills
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
        echo "Usage: ./kilo-skills.sh [skills|list|backup|restore]"
        exit 1
        ;;
esac