#!/usr/bin/env bash
#
# install.sh — One-stop dotfiles installer
#
# Usage:
#   git clone <repo-url> ~/dotfiles && cd ~/dotfiles && ./install.sh
#
# What it does:
#   1. Installs oh-my-zsh (if not already installed).
#   2. Installs cargo (Rust) (if not already installed).
#   3. Installs stow     (if not already installed).
#   4. Installs node (Node.js) (if not already installed).
#   5. Backs up any conflicting dotfiles to ~/.dotfiles_backup.
#   6. Uses GNU Stow to symlink this repo's dotfiles into $HOME.
#   7. Links ~/.ssh/config and the 1Password public key, and authorizes that
#      key for logins to this machine (~/.ssh itself is never stowed).
#   8. Creates ~/.zsh_extra if it does not exist.
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

# ─── 2. Install cargo (Rust) ──────────────────────────────────────────────────

install_cargo() {
    if command -v cargo &>/dev/null; then
        ok "cargo is already installed."
        return
    fi

    info "cargo not found. Attempting to install …"

    if command -v brew &>/dev/null; then
        brew install rustup
    elif command -v apt-get &>/dev/null; then
        # Install curl first if not present
        if ! command -v curl &>/dev/null; then
            sudo apt-get update -qq && sudo apt-get install -y -qq curl
        fi
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    elif command -v dnf &>/dev/null; then
        sudo dnf install -y rust cargo
    elif command -v pacman &>/dev/null; then
        sudo pacman -S --noconfirm rust
    else
        error "Could not detect a supported package manager (apt, brew, dnf, pacman)."
        error "Please install Rust manually and re-run this script."
        exit 1
    fi

    ok "cargo installed."
}

# ─── 3. Install stow ──────────────────────────────────────────────────────────

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

# ─── 4. Install node (Node.js) ────────────────────────────────────────────────

install_node() {
    if command -v node &>/dev/null; then
        node_version=$(node --version 2>/dev/null || true)
        if [ -n "$node_version" ]; then
            ok "node ($node_version) is already installed."
            return
        fi
    fi

    info "node not found. Attempting to install …"

    if command -v brew &>/dev/null; then
        brew install node
    elif command -v apt-get &>/dev/null; then
        # Install via NodeSource repository for newer versions
        if ! command -v curl &>/dev/null; then
            sudo apt-get update -qq && sudo apt-get install -y -qq curl
        fi
        curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
        sudo apt-get install -y -qq nodejs
    elif command -v dnf &>/dev/null; then
        # Enable NodeSource repository
        if ! command -v curl &>/dev/null; then
            sudo dnf install -y curl
        fi
        curl -fsSL https://rpm.nodesource.com/setup_lts.x | sudo bash -
        sudo dnf install -y nodejs
    elif command -v pacman &>/dev/null; then
        sudo pacman -S --noconfirm nodejs npm
    else
        error "Could not detect a supported package manager (apt, brew, dnf, pacman)."
        error "Please install Node.js manually and re-run this script."
        exit 1
    fi

    ok "node installed."
}

# ─── 5. Back up conflicting dotfiles ──────────────────────────────────────────

backup_conflicts() {
    # Build the list of files/dirs that stow would create in $HOME.
    # We look at the repo root for dotfiles (files/dirs starting with '.')
    # and the .config directory contents, skipping items in .stow-local-ignore.
    local dominated_files=()

    # Collect top-level dotfiles/dirs managed by this repo
    for item in "$DOTFILES_DIR"/.*; do
        base="$(basename "$item")"
        # Skip . , .. , .git, .gitignore, .stow-local-ignore, .DS_Store, .pi, .ssh
        # (.pi and .ssh hold live state; individual files inside them are
        # managed via file-level symlinks, see link_pi_agent_files/link_ssh_files)
        case "$base" in
            .|..|.git|.gitignore|.stow-local-ignore|.DS_Store|.pi|.ssh) continue ;;
        esac
        dominated_files+=("$base")
    done

    local dominated=0

    for f in "${dominated_files[@]}"; do
        target="$HOME/$f"
        # Only a conflict if it exists AND is NOT already a symlink into our repo
        if [ -e "$target" ] || [ -L "$target" ]; then
            if [ -L "$target" ]; then
                # It's a symlink — only skip if it already points into our repo
                local link_dest
                link_dest="$(readlink -f "$target" 2>/dev/null || true)"
                case "$link_dest" in
                    "$DOTFILES_DIR"/*) continue ;;  # already managed by us
                esac
            fi
            # Real file, directory, or symlink pointing elsewhere → conflict
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
            if [ -e "$target" ] || [ -L "$target" ]; then
                if [ -L "$target" ]; then
                    local link_dest
                    link_dest="$(readlink -f "$target" 2>/dev/null || true)"
                    case "$link_dest" in "$DOTFILES_DIR"/*) continue ;; esac
                fi
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
        if [ -e "$target" ] || [ -L "$target" ]; then
            if [ -L "$target" ]; then
                local link_dest
                link_dest="$(readlink -f "$target" 2>/dev/null || true)"
                case "$link_dest" in "$DOTFILES_DIR"/*) continue ;; esac
            fi
            info "Backing up $target → $BACKUP_DIR/$f"
            # If a previous backup exists, remove it first to avoid errors
            if [ -n "$f" ] && [ -e "$BACKUP_DIR/$f" ]; then
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
    # .pi is ignored: ~/.pi holds live state (auth, sessions); only
    # ~/.pi/agent/models.json and ~/.pi/agent/settings.json are managed, via
    # file-level symlinks (see link_pi_agent_files).
    if ! stow --restow --target="$HOME" --dir="$DOTFILES_DIR" --ignore='.pi' .; then
        error "stow failed. Check for conflicting files or permission issues."
        error "You may need to manually resolve conflicts and re-run this script."
        exit 1
    fi
    ok "Dotfiles linked into $HOME."
}

# ─── 4b. Link pi agent config (file-level, ~/.pi is not stowed) ──────────────

link_pi_agent_files() {
    local files=("models.json" "settings.json")
    local file src dst

    for file in "${files[@]}"; do
        src="$DOTFILES_DIR/.pi/agent/$file"
        dst="$HOME/.pi/agent/$file"
        if [ ! -f "$src" ]; then
            ok "No .pi/agent/$file in repo; skipping."
            continue
        fi

        mkdir -p "$HOME/.pi/agent"

        if [ -L "$dst" ]; then
            local link_dest
            link_dest="$(readlink -f "$dst" 2>/dev/null || true)"
            if [ "$link_dest" = "$(readlink -f "$src")" ]; then
                ok "~/.pi/agent/$file already linked to repo."
                continue
            fi
            info "Re-pointing existing symlink $dst"
            rm "$dst"
        elif [ -e "$dst" ]; then
            info "Backing up $dst → $BACKUP_DIR/.pi-agent-$file"
            mkdir -p "$BACKUP_DIR"
            mv "$dst" "$BACKUP_DIR/.pi-agent-$file"
        fi

        ln -s "$src" "$dst"
        ok "Linked $dst → $src"
    done
}

# ─── 4c. Link SSH config + 1Password key (file-level, ~/.ssh is not stowed) ──
#
# ~/.ssh must stay a real directory: if stow folded it into the repo, private
# keys and known_hosts would land in the git working tree. So only two files
# are linked: the tracked config and the 1Password public key. The public key
# is also appended to ~/.ssh/authorized_keys so that this machine accepts the
# one key that lives in 1Password.

link_ssh_files() {
    local ssh_dir="$HOME/.ssh"

    if [ -L "$ssh_dir" ]; then
        error "$ssh_dir is a symlink; it must be a real directory. Refusing to touch it."
        exit 1
    fi
    mkdir -p "$ssh_dir"
    chmod 700 "$ssh_dir"

    # A hand-written ~/.ssh/config becomes ~/.ssh/config.local, which the
    # tracked config Includes first (so its entries keep winning).
    local cfg="$ssh_dir/config"
    if [ -f "$cfg" ] && [ ! -L "$cfg" ]; then
        local dest="$ssh_dir/config.local"
        if [ -e "$dest" ]; then
            mkdir -p "$ssh_dir/config.d"
            dest="$ssh_dir/config.d/migrated-$(date +%Y%m%d%H%M%S)"
        fi
        info "Moving unmanaged $cfg → $dest"
        mv "$cfg" "$dest"
    fi
    [ -e "$ssh_dir/config.local" ] || : > "$ssh_dir/config.local"

    local file src dst link_dest
    for file in config id_1password.pub; do
        src="$DOTFILES_DIR/.ssh/$file"
        dst="$ssh_dir/$file"
        [ -f "$src" ] || { ok "No .ssh/$file in repo; skipping."; continue; }

        if [ -L "$dst" ]; then
            link_dest="$(readlink -f "$dst" 2>/dev/null || true)"
            if [ "$link_dest" = "$(readlink -f "$src")" ]; then
                ok "~/.ssh/$file already linked to repo."
                continue
            fi
            info "Re-pointing existing symlink $dst"
            rm "$dst"
        elif [ -e "$dst" ]; then
            info "Backing up $dst → $BACKUP_DIR/.ssh-$file"
            mkdir -p "$BACKUP_DIR"
            mv "$dst" "$BACKUP_DIR/.ssh-$file"
        fi
        ln -s "$src" "$dst"
        ok "Linked $dst → $src"
    done

    authorize_1password_key
}

authorize_1password_key() {
    local pub="$DOTFILES_DIR/.ssh/id_1password.pub"
    local ak="$HOME/.ssh/authorized_keys"
    [ -f "$pub" ] || return 0

    local blob
    blob="$(awk '{ print $2 }' "$pub")"
    touch "$ak"
    chmod 600 "$ak"
    if grep -qF -- "$blob" "$ak"; then
        ok "1Password key already in ~/.ssh/authorized_keys."
        return 0
    fi
    # Keep the file well-formed if it currently lacks a trailing newline.
    if [ -s "$ak" ] && [ -n "$(tail -c1 "$ak")" ]; then
        echo >> "$ak"
    fi
    cat "$pub" >> "$ak"
    ok "Added 1Password key to ~/.ssh/authorized_keys."
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
    install_cargo
    install_stow
    install_node
    backup_conflicts
    stow_dotfiles
    link_pi_agent_files
    link_ssh_files
    create_zsh_extra

    echo ""
    ok "All done! Open a new terminal or run 'exec zsh' to apply changes."
    echo ""
}

main "$@"
