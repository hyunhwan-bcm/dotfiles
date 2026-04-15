#!/usr/bin/env bash
#
# install.sh — One-stop dotfiles installer
#
# Usage:
#   git clone <repo-url> ~/dotfiles && cd ~/dotfiles && ./install.sh
#
# What it does:
#   1. Installs oh-my-zsh (if not already installed).
#   2. Installs stow     (if not already installed).
#   3. Backs up any conflicting dotfiles to ~/.dotfiles_backup.
#   4. Uses GNU Stow to symlink this repo's dotfiles into $HOME.
#   5. Creates ~/.zsh_extra if it does not exist.
#
# Safe to run multiple times (idempotent).
#

set -euo pipefail

# ─── Helpers ───────────────────────────────────────────────────────────────────

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"
BACKUP_DIR="$HOME/.dotfiles_backup"

info()  { printf '\033[1;34m[INFO]\033[0m  %s\n' "$*"; }
warn()  { printf '\033[1;33m[WARN]\033[0m  %s\n' "$*"; }
error() { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*"; }
ok()    { printf '\033[1;32m[OK]\033[0m    %s\n' "$*"; }

# ─── 1. Install oh-my-zsh ─────────────────────────────────────────────────────

install_oh_my_zsh() {
    if [ -d "$HOME/.oh-my-zsh" ]; then
        ok "oh-my-zsh is already installed."
    else
        info "Installing oh-my-zsh …"
        # RUNZSH=no  → don't launch zsh after install
        # KEEP_ZSHRC=yes → don't overwrite .zshrc (we manage it via stow)
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" \
            --unattended
        ok "oh-my-zsh installed."
    fi
}

# ─── 2. Install stow ──────────────────────────────────────────────────────────

install_stow() {
    if command -v stow &>/dev/null; then
        ok "stow is already installed."
        return
    fi

    info "stow not found. Attempting to install …"

    if command -v apt-get &>/dev/null; then
        sudo apt-get update -qq && sudo apt-get install -y -qq stow
    elif command -v brew &>/dev/null; then
        brew install stow
    elif command -v dnf &>/dev/null; then
        sudo dnf install -y stow
    elif command -v pacman &>/dev/null; then
        sudo pacman -S --noconfirm stow
    else
        error "Could not detect a supported package manager (apt, brew, dnf, pacman)."
        error "Please install GNU Stow manually and re-run this script."
        exit 1
    fi

    ok "stow installed."
}

# ─── 3. Back up conflicting dotfiles ──────────────────────────────────────────

backup_conflicts() {
    # Build the list of files/dirs that stow would create in $HOME.
    # We look at the repo root for dotfiles (files/dirs starting with '.')
    # and the .config directory contents, skipping items in .stow-local-ignore.
    local dominated_files=()

    # Collect top-level dotfiles/dirs managed by this repo
    for item in "$DOTFILES_DIR"/.*; do
        base="$(basename "$item")"
        # Skip . , .. , .git, .gitignore, .stow-local-ignore, .DS_Store
        case "$base" in
            .|..|.git|.gitignore|.stow-local-ignore|.DS_Store) continue ;;
        esac
        dominated_files+=("$base")
    done

    local dominated=0

    for f in "${dominated_files[@]}"; do
        target="$HOME/$f"
        # Only a conflict if it exists AND is NOT already a symlink into our repo
        if [ -e "$target" ] && ! [ -L "$target" ]; then
            dominated=1
            break
        fi
    done

    if [ "$dominated" -eq 0 ]; then
        ok "No conflicting dotfiles found."
        return
    fi

    # Prompt user (auto-yes when running non-interactively, e.g. in CI)
    if [ -t 0 ]; then
        warn "The following existing files/directories would conflict:"
        for f in "${dominated_files[@]}"; do
            target="$HOME/$f"
            if [ -e "$target" ] && ! [ -L "$target" ]; then
                echo "  • $target"
            fi
        done
        printf '\n'
        read -rp "Move them to $BACKUP_DIR and continue? [y/N] " answer
        case "$answer" in
            [yY]|[yY][eE][sS]) ;;
            *)
                error "Aborted by user."
                exit 1
                ;;
        esac
    else
        info "Non-interactive mode: automatically backing up conflicting files."
    fi

    mkdir -p "$BACKUP_DIR"

    for f in "${dominated_files[@]}"; do
        target="$HOME/$f"
        if [ -e "$target" ] && ! [ -L "$target" ]; then
            info "Backing up $target → $BACKUP_DIR/$f"
            # If a previous backup exists, remove it first to avoid errors
            if [ -e "$BACKUP_DIR/$f" ]; then
                rm -rf "$BACKUP_DIR/$f"
            fi
            mv "$target" "$BACKUP_DIR/$f"
        fi
    done

    ok "Conflicting files backed up to $BACKUP_DIR."
}

# ─── 4. Stow dotfiles ─────────────────────────────────────────────────────────

stow_dotfiles() {
    info "Linking dotfiles with stow …"
    # --restow re-creates symlinks (idempotent)
    stow --restow --target="$HOME" --dir="$DOTFILES_DIR" .
    ok "Dotfiles linked into $HOME."
}

# ─── 5. Create ~/.zsh_extra ───────────────────────────────────────────────────

create_zsh_extra() {
    if [ -f "$HOME/.zsh_extra" ]; then
        ok "~/.zsh_extra already exists."
    else
        info "Creating ~/.zsh_extra …"
        cat > "$HOME/.zsh_extra" <<'EOF'
# ~/.zsh_extra
# Put machine-specific or private shell configuration here.
# This file is sourced at the end of .zshrc and is NOT tracked by git.
EOF
        ok "~/.zsh_extra created."
    fi
}

# ─── Main ──────────────────────────────────────────────────────────────────────

main() {
    echo ""
    info "=== Dotfiles Installer ==="
    echo ""

    install_oh_my_zsh
    install_stow
    backup_conflicts
    stow_dotfiles
    create_zsh_extra

    echo ""
    ok "All done! Open a new terminal or run 'exec zsh' to apply changes."
    echo ""
}

main "$@"
