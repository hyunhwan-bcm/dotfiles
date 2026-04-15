dotfiles
========

## Quick Start

```bash
git clone https://github.com/hyunhwan-bcm/dotfiles.git ~/dotfiles
cd ~/dotfiles
./install.sh
```

## What `install.sh` Does

1. **Installs oh-my-zsh** — skipped if `~/.oh-my-zsh` already exists.
2. **Installs GNU Stow** — via `apt`, `brew`, `dnf`, or `pacman`; skipped if already installed.
3. **Backs up conflicting dotfiles** — existing files that would conflict are moved to `~/.dotfiles_backup`. You will be prompted before anything is overwritten.
4. **Symlinks dotfiles** — uses `stow` to create symlinks from this repo into `$HOME`.
5. **Creates `~/.zsh_extra`** — a machine-specific config file sourced by `.zshrc`. It is *not* tracked by git.

The script is **idempotent**: running it multiple times is safe.

## Files Managed

| File / Directory | Purpose |
|---|---|
| `.zshrc` | Zsh configuration (oh-my-zsh, plugins, aliases) |
| `.gitconfig` | Git settings |
| `.tmux.conf` | tmux configuration |
| `.config/kitty/` | Kitty terminal settings |
| `.config/nvim/` | Neovim configuration |

## `.zsh_extra`

`~/.zsh_extra` is sourced at the end of `.zshrc`. Use it for machine-specific
settings, secrets, or overrides that should not be committed to this repo.
