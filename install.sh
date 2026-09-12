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
#   7. Creates ~/.zsh_extra if it does not exist.
#   8. Adds `Include ~/.config/ssh/tailnet.conf` to ~/.ssh/config so the
#      shared Tailscale host aliases are available to ssh/scp/rsync.
#   9. Installs the PR review stack used by .gitconfig and .config/gh-dash:
#      git-delta (git pager), diffnav (gh-dash diff pager) and the gh-dash
#      extension for the GitHub CLI. Best effort: a missing package manager
#      only prints a warning.
#  10. Symlinks the runnable scripts in tools/ into ~/.local/bin (so
#      `gh-pr-notify` works in any shell, not just interactive zsh).
#  11. macOS: loads a launchd agent that runs tools/gh-pr-notify.sh every
#      5 minutes for desktop notifications about pull request activity.
#
# Safe to run multiple times (idempotent).
#
# install.sh --post-update
#   Non-interactive subset used by the auto-updater (tools/check_for_update.zsh)
#   after a git pull: re-stow, re-link pi files, ensure the ssh Include. Never
#   installs packages or prompts; skips stow quietly if it is not installed.
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
        # Skip . , .. , .git, .gitignore, .stow-local-ignore, .DS_Store, .pi
        # (.pi holds live state; agent/models.json and agent/settings.json are
        # managed, via symlinks)
        case "$base" in
            .|..|.git|.gitignore|.stow-local-ignore|.DS_Store|.pi) continue ;;
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

# Same as stow_dotfiles, but for the auto-updater: no exit on a missing stow
# (a pull should not fail because a machine lacks stow), and a failure is
# reported as a non-zero return so the updater can show it.
restow_quietly() {
    if ! command -v stow &>/dev/null; then
        warn "stow not installed; new files were not linked. Run ./install.sh."
        return 0
    fi
    if ! stow --restow --target="$HOME" --dir="$DOTFILES_DIR" --ignore='.pi' . 2>&1; then
        error "stow --restow failed; fix the conflict above, then run ./install.sh"
        return 1
    fi
    ok "Dotfiles re-linked into $HOME."
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

# ─── 6. Wire shared SSH config into ~/.ssh/config ─────────────────────────────
# ~/.ssh itself is NOT stowed (it holds keys and known_hosts). Instead the
# tailnet host aliases live in .config/ssh/tailnet.conf and ~/.ssh/config just
# includes them. `Include` must appear before any `Host` block, so it goes at
# the top of the file.

ensure_ssh_include() {
    local ssh_dir="$HOME/.ssh"
    local ssh_cfg="$ssh_dir/config"
    local line='Include ~/.config/ssh/tailnet.conf'

    if [ ! -f "$DOTFILES_DIR/.config/ssh/tailnet.conf" ]; then
        ok "No .config/ssh/tailnet.conf in repo; skipping."
        return
    fi

    mkdir -p "$ssh_dir"
    chmod 700 "$ssh_dir"

    if [ -f "$ssh_cfg" ] && grep -qxF "$line" "$ssh_cfg"; then
        ok "~/.ssh/config already includes tailnet.conf."
        return
    fi

    info "Adding '$line' to ~/.ssh/config …"
    if [ -f "$ssh_cfg" ]; then
        { printf '%s\n' "$line"; cat "$ssh_cfg"; } > "$ssh_cfg.tmp"
        mv "$ssh_cfg.tmp" "$ssh_cfg"
    else
        printf '%s\n' "$line" > "$ssh_cfg"
    fi
    chmod 600 "$ssh_cfg"
    ok "~/.ssh/config now includes tailnet.conf."
}

# ─── 7. PR review tools: git-delta, diffnav, gh-dash ─────────────────────────
# .gitconfig sets core.pager = delta and .config/gh-dash/config.yml sets
# pager.diff = diffnav, so both binaries should exist on every machine that
# uses these dotfiles. Nothing here is fatal: on a box without a supported
# package manager we warn and move on so the rest of the install still runs.

install_pr_review_tools() {
    # git-delta — packaged as "git-delta" everywhere, binary is "delta".
    if command -v delta &>/dev/null; then
        ok "delta is already installed."
    else
        info "delta not found. Attempting to install git-delta …"
        if command -v brew &>/dev/null; then
            brew install git-delta
        elif command -v apt-get &>/dev/null; then
            sudo apt-get update -qq && sudo apt-get install -y -qq git-delta \
                || warn "git-delta is not in this apt repo; see https://dandavison.github.io/delta/installation.html"
        elif command -v dnf &>/dev/null; then
            sudo dnf install -y git-delta
        elif command -v pacman &>/dev/null; then
            sudo pacman -S --noconfirm git-delta
        else
            warn "No supported package manager; install git-delta manually (core.pager = delta needs it)."
        fi
        command -v delta &>/dev/null && ok "delta installed."
    fi

    # diffnav — Homebrew formula on macOS/Linuxbrew, otherwise via Go.
    if command -v diffnav &>/dev/null; then
        ok "diffnav is already installed."
    else
        info "diffnav not found. Attempting to install …"
        if command -v brew &>/dev/null; then
            brew install diffnav
        elif command -v go &>/dev/null; then
            go install github.com/dlvhdr/diffnav@latest
        else
            warn "Neither brew nor go found; grab a release from https://github.com/dlvhdr/diffnav/releases"
        fi
        command -v diffnav &>/dev/null && ok "diffnav installed."
    fi

    # terminal-notifier — clickable macOS notifications for tools/gh-pr-notify.sh.
    if [ "$(uname -s)" = "Darwin" ] && command -v brew &>/dev/null; then
        if command -v terminal-notifier &>/dev/null; then
            ok "terminal-notifier is already installed."
        else
            info "Installing terminal-notifier …"
            brew install terminal-notifier && ok "terminal-notifier installed."
        fi
    fi

    # GitHub CLI + gh-dash extension.
    if ! command -v gh &>/dev/null; then
        info "gh (GitHub CLI) not found. Attempting to install …"
        if command -v brew &>/dev/null; then
            brew install gh
        elif command -v dnf &>/dev/null; then
            sudo dnf install -y gh
        elif command -v pacman &>/dev/null; then
            sudo pacman -S --noconfirm github-cli
        else
            warn "Install gh manually: https://github.com/cli/cli#installation (apt needs the GitHub repo first)."
        fi
    fi

    if ! command -v gh &>/dev/null; then
        warn "gh is not available; skipping the gh-dash extension."
        return 0
    fi

    if gh extension list 2>/dev/null | grep -q 'dlvhdr/gh-dash'; then
        ok "gh-dash extension is already installed."
    elif gh auth status &>/dev/null; then
        info "Installing gh-dash extension …"
        gh extension install dlvhdr/gh-dash && ok "gh-dash installed (run: gh dash)."
    else
        warn "gh is not logged in; run 'gh auth login' then 'gh extension install dlvhdr/gh-dash'."
    fi
}

# ─── 8. Link repo tools into ~/.local/bin ────────────────────────────────────
# tools/ holds scripts meant to be run by hand as well as by launchd/cron.
# A shell alias would only exist in interactive zsh, so these get a real
# symlink on PATH instead: that works in scripts, in launchd, and in
# `command -v` checks. ~/.local/bin is the XDG-ish default and is already on
# PATH in .zshrc's environment on most machines; we add it if it is missing.

link_repo_bins() {
    local bin_dir="$HOME/.local/bin"
    local tools=("gh-pr-notify.sh")
    local tool src dst name

    mkdir -p "$bin_dir"

    for tool in "${tools[@]}"; do
        src="$DOTFILES_DIR/tools/$tool"
        name="${tool%.sh}"
        dst="$bin_dir/$name"

        [ -f "$src" ] || continue
        chmod +x "$src" 2>/dev/null || true

        if [ -L "$dst" ] && [ "$(readlink -f "$dst" 2>/dev/null)" = "$(readlink -f "$src")" ]; then
            ok "$name already linked into ~/.local/bin."
            continue
        fi
        if [ -e "$dst" ] && [ ! -L "$dst" ]; then
            warn "$dst exists and is not a symlink; leaving it alone."
            continue
        fi
        ln -sfn "$src" "$dst"
        ok "Linked $dst → $src"
    done

    case ":$PATH:" in
        *":$bin_dir:"*) ;;
        *) warn "~/.local/bin is not on PATH; add it in ~/.zsh_extra: export PATH=\"$HOME/.local/bin:$PATH\"" ;;
    esac
}

# ─── 9. GitHub PR notifications (macOS launchd agent) ────────────────────────
# Renders tools/launchd/com.hyunhwan.dotfiles.gh-pr-notify.plist into
# ~/Library/LaunchAgents and (re)loads it, so tools/gh-pr-notify.sh runs every
# 5 minutes. Idempotent: nothing is reloaded when the rendered plist is
# unchanged and the agent is already running. Skipped silently off macOS.

install_gh_pr_notify_agent() {
    [ "$(uname -s)" = "Darwin" ] || return 0

    local label="com.hyunhwan.dotfiles.gh-pr-notify"
    local template="$DOTFILES_DIR/tools/launchd/$label.plist"
    local dst="$HOME/Library/LaunchAgents/$label.plist"

    if [ ! -f "$template" ]; then
        ok "No launchd template for gh-pr-notify in repo; skipping."
        return 0
    fi

    mkdir -p "$HOME/Library/LaunchAgents" "$HOME/.local/state/gh-pr-notify"
    local rendered
    rendered="$(mktemp)"
    sed "s|__HOME__|$HOME|g" "$template" > "$rendered"

    if [ -f "$dst" ] && cmp -s "$rendered" "$dst" \
        && launchctl print "gui/$(id -u)/$label" &>/dev/null; then
        ok "gh-pr-notify launchd agent is already installed and loaded."
        rm -f "$rendered"
        return 0
    fi

    mv "$rendered" "$dst"
    chmod 644 "$dst"
    # bootout fails harmlessly when the agent is not loaded yet.
    launchctl bootout "gui/$(id -u)/$label" &>/dev/null || true
    if launchctl bootstrap "gui/$(id -u)" "$dst"; then
        ok "gh-pr-notify launchd agent loaded (every 5 min; logs in ~/.local/state/gh-pr-notify/launchd.log)."
    else
        warn "Could not load $dst; run: launchctl bootstrap gui/$(id -u) $dst"
    fi
}

# ─── Main ──────────────────────────────────────────────────────────────────────

post_update() {
    # Called by tools/check_for_update.zsh after a successful git pull.
    restow_quietly || return 1
    link_pi_agent_files
    ensure_ssh_include
    link_repo_bins
    install_gh_pr_notify_agent
}

main() {
    if [ "${1:-}" = "--post-update" ]; then
        post_update
        return
    fi

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
    create_zsh_extra
    ensure_ssh_include
    install_pr_review_tools
    link_repo_bins
    install_gh_pr_notify_agent

    echo ""
    ok "All done! Open a new terminal or run 'exec zsh' to apply changes."
    echo ""
}

main "$@"
