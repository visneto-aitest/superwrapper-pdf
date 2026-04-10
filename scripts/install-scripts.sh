#!/usr/bin/env bash
# install-scripts.sh - Install AI scripts to ~/ai-scripts/
#
# Installs all scripts from scripts/ to ~/ai-scripts/ with optional environment support.
#
# Usage:
#   install-scripts.sh                  Install to default ~/ai-scripts/
#   install-scripts.sh <environment>     Install to ~/ai-scripts/<environment>/
#   install-scripts.sh --uninstall       Remove installed scripts
#   install-scripts.sh --link            Create symlinks instead of copying

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_TARGET="${HOME}/ai-scripts"

usage() {
    cat << 'USAGE'
Install AI Scripts

Usage: install-scripts.sh [options] [environment]

Options:
  --uninstall    Remove installed scripts
  --link         Create symlinks instead of copying
  --help         Show this help

Arguments:
  environment     Target directory (default: ~/ai-scripts/)

Examples:
  install-scripts.sh                    # Install to ~/ai-scripts/
  install-scripts.sh work               # Install to ~/ai-scripts/work/
  install-scripts.sh --uninstall        # Remove installed scripts
  install-scripts.sh --link kilo        # Symlink to ~/ai-scripts/kilo/
USAGE
    exit 0
}

uninstall_scripts() {
    local target="${1:-$DEFAULT_TARGET}"
    
    if [ ! -d "$target" ]; then
        echo "No installation found at $target"
        return
    fi
    
    echo "Removing scripts from $target..."
    rm -rf "$target"
    echo "✅ Uninstalled scripts from $target"
}

install_scripts() {
    local target="$1"
    local use_link="${2:-false}"
    
    mkdir -p "$target"
    
    echo "Installing scripts to $target..."
    
    if [ "$use_link" = "true" ]; then
        for item in "$SCRIPT_DIR"/*; do
            local name
            name=$(basename "$item")
            
            [ "$name" = "install-scripts.sh" ] && continue
            [ "$name" = "lib" ] && continue
            
            local dest="$target/$name"
            
            if [ -L "$dest" ]; then
                rm "$dest"
            fi
            
            ln -sf "$item" "$dest"
            echo "  Linked: $name"
        done
        
        if [ -d "$SCRIPT_DIR/lib" ]; then
            mkdir -p "$target/lib"
            for item in "$SCRIPT_DIR/lib"/*; do
                [ -f "$item" ] || continue
                local name
                name=$(basename "$item")
                local dest="$target/lib/$name"
                
                if [ -L "$dest" ]; then
                    rm "$dest"
                fi
                
                ln -sf "$item" "$dest"
                echo "  Linked: lib/$name"
            done
        fi
    else
        rsync -av --exclude='__pycache__' \
            --exclude='*.pyc' \
            --exclude='install-scripts.sh' \
            "$SCRIPT_DIR/" "$target/"
        echo "  Copied all files"
    fi
    
    echo ""
    echo "✅ Installed to $target"
    echo ""
    echo "Add to your shell profile (.zshrc/.bashrc):"
    echo "  export PATH=\"$target:\$PATH\""
}

main() {
    local use_link=false
    local target="$DEFAULT_TARGET"
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --help|-h)
                usage
                ;;
            --uninstall)
                uninstall_scripts "$target"
                exit 0
                ;;
            --link)
                use_link=true
                shift
                ;;
            *)
                if [[ "$1" =~ ^[a-zA-Z0-9_-]+$ ]]; then
                    target="$DEFAULT_TARGET/$1"
                fi
                shift
                ;;
        esac
    done
    
    install_scripts "$target" "$use_link"
}

main "$@"
