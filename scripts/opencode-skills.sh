#!/bin/bash

# opencode-skills.sh - Find all installed skills for opencode in global and project contexts

echo "=== OpenCode Skills Inventory ==="
echo

# Global skills locations
GLOBAL_PATHS=(
    "$HOME/.opencode/skills"
    "$HOME/.local/share/opencode/skills"
    "/usr/local/share/opencode/skills"
    "/opt/opencode/skills"
    "$HOME/.config/opencode/skills"
    "$HOME/.config/opencode/skill_bak"  # observed backup location
)

# Project skills locations (relative to current directory)
PROJECT_PATHS=(
    "./.opencode/skills"
    "./opencode_skills"
    "./skills"
    "../.opencode/skills"  # Check parent directory too
)

# Function to list skills in a given path
list_skills() {
    local path="$1"
    local context="$2"
    
    if [[ -d "$path" ]]; then
        echo "[$context] Skills in: $path"
        # First, try to find skill descriptor files (SKILL.md, skill.yaml, etc.)
        local tmpfile=$(mktemp)
        find "$path" -type f \( -name "SKILL.md" -o -name "skill.yaml" -o -name "skill.yml" -o -name "skill.json" \) -exec dirname {} \; | sort -u > "$tmpfile"
        
        if [[ -s "$tmpfile" ]]; then
            # We found descriptor files, list the directories containing them (unique)
            while read skill_dir; do
                # Get relative path from $path to skill_dir
                local rel_path="${skill_dir#$path/}"
                # If rel_path is empty, it means the descriptor is directly in $path (unlikely for a skill)
                if [[ -z "$rel_path" ]]; then
                    rel_path="."
                fi
                echo "  - $rel_path"
            done < "$tmpfile"
        else
            # No descriptor files found, fallback to listing leaf directories (directories with no subdirectories)
            local leaf_tmp=$(mktemp)
            find "$path" -type d 2>/dev/null | while read dir; do
                # Check if this directory has any subdirectories
                if [[ -z "$(find "$dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)" ]]; then
                    echo "$dir"
                fi
            done | sort -u > "$leaf_tmp"
            
            if [[ -s "$leaf_tmp" ]]; then
                while read leaf_dir; do
                    # Get relative path from $path to leaf_dir
                    local rel_path="${leaf_dir#$path/}"
                    # If rel_path is empty, skip (should not happen because leaf_dir is under $path and not equal to $path? Actually, if $path is a leaf directory itself, then rel_path would be empty. We'll skip that case.)
                    if [[ -n "$rel_path" ]]; then
                        echo "  - $rel_path"
                    fi
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
        list_skills "$gp" "Global"
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
        list_skills "$pp" "Project"
        found_project=true
    fi
done
if [[ "$found_project" == false ]]; then
    echo "  No project skills found."
    echo
fi

# If opencode command exists, try to get skills from it
if command -v opencode &> /dev/null; then
    echo "Additional info from opencode command:"
    opencode skills list 2>/dev/null || echo "  Could not retrieve skills via opencode command"
fi