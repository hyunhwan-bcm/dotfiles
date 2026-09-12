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
5. **Links Pi agent config** — `~/.pi/agent/models.json` and `~/.pi/agent/settings.json` are symlinked into this repo (file-level, since `~/.pi` is not stowed).
6. **Creates `~/.zsh_extra`** — a machine-specific config file sourced by `.zshrc`. It is *not* tracked by git.
7. **Wires SSH config** — adds `Include ~/.config/ssh/tailnet.conf` to `~/.ssh/config` so `ssh studio`, `ssh jani` etc. work on every machine.
8. **Installs PR review tools** — `git-delta` (git pager), `diffnav` (gh-dash diff pager) `terminal-notifier` (macOS) and the `gh-dash` extension for the GitHub CLI. Best effort: warns and continues if a package manager is missing.
9. **Links `tools/` scripts into `~/.local/bin`** — so `gh-pr-notify` is a normal command in any shell.
10. **Loads the PR notifier (macOS)** — a launchd agent runs `tools/gh-pr-notify.sh` every 5 minutes and posts a desktop notification for new pull request activity (review requests, mentions, comments, CI, merges). Click a notification to open the PR. Also re-rendered by `--post-update`.

The script is **idempotent**: running it multiple times is safe.

## Files Managed

| File / Directory | Purpose |
|---|---|
| `.zshrc` | Zsh configuration (oh-my-zsh, vi-mode keybindings with mode indicator, aliases) |
| `tools/check_for_update.zsh` | Daily background self-update of this repo, see below |
| `tools/gh-pr-notify.sh` | GitHub PR desktop notifications via the notifications API; `gh-pr-notify --list` shows pending items, `--test` sends a sample. Tune with `GH_PR_NOTIFY_REASONS` / `GH_PR_NOTIFY_TYPES` in `~/.zsh_extra` or the plist |
| `tools/launchd/*.plist` | launchd template for the notifier, rendered into `~/Library/LaunchAgents` by `install.sh` |
| `.gitconfig` | Git settings; `core.pager = delta` with line numbers, `n`/`N` file navigation and word-level diff highlighting |
| `.config/gh-dash/config.yml` | [gh-dash](https://github.com/dlvhdr/gh-dash) PR/issue dashboard; `d` opens the PR diff in [diffnav](https://github.com/dlvhdr/diffnav) (file tree + delta rendering, unified by default, `s` toggles side-by-side) |
| `.config/kitty/` | Kitty terminal settings |
| `.config/nvim/` | Neovim configuration |
| `.config/yazi/` | Yazi file manager: `vfs.toml` registers every Tailscale node as an `sftp://` filesystem, `keymap.toml` adds `g`+letter jumps to them |
| `.config/ssh/tailnet.conf` | SSH host aliases for the Tailscale nodes, included from `~/.ssh/config` by `install.sh` |
| `.pi/agent/models.json` | Pi agent model config (file-level symlink, not stowed) |
| `.pi/agent/settings.json` | Pi agent settings (file-level symlink, not stowed) |

## Automatic updates

Every interactive shell sources `tools/check_for_update.zsh`, modeled on
oh-my-zsh's `check_for_upgrade.sh`. Once a day it forks a background job after
the first prompt, so startup never waits on the network. The job fetches and,
if the branch is behind its upstream, runs `git pull --rebase` with
`rebase.autoStash`, so local edits to tracked files (nvim's `lazy-lock.json`,
say) are stashed and re-applied instead of blocking the update. Untracked files
are ignored; apps drop state under `~/.config`, which is a symlink into this
repo. After a pull it runs `install.sh --post-update` to re-stow, so new files
get their symlinks. The result shows up at the next prompt:

```
[dotfiles] updated 8e68fcc..60ab3e7 (3 new commit(s)). Open a new shell to pick up changes.
```

Errors (a conflicting local change, a rebase in progress, no upstream) are
reported the same way and the repo is left for you to sort out. Being offline
is not reported.

Settings, in `~/.zsh_extra`:

```zsh
zstyle ':dotfiles:update' mode reminder   # auto (default) | reminder | disabled
zstyle ':dotfiles:update' frequency 7     # days between checks, default 1
```

`dotfiles-update` (alias `df-update`) updates right now, in the foreground.
State lives in `~/.cache/dotfiles/update`.

## Tests

```bash
# updater, in a sandbox home (also runs on macOS)
HOME=$(mktemp -d) zsh tests/docker/update_test.sh

# same, inside Debian
docker build -f tests/docker/Dockerfile.update-test -t dotfiles-update-test . && docker run --rm dotfiles-update-test

# full install smoke test
docker build -f tests/docker/Dockerfile -t dotfiles-smoke . && docker run --rm dotfiles-smoke
```

## `.zsh_extra`

`~/.zsh_extra` is sourced at the end of `.zshrc`. Use it for machine-specific
settings, secrets, or overrides that should not be committed to this repo.
# dotfiles

Personal dotfiles for macOS and Linux. The repository is intended to be linked
into `$HOME` with GNU Stow, so files stay versioned here while appearing at their
normal runtime paths.

## Quick start

Install GNU Stow first:

```sh
# macOS
brew install stow

# Debian/Ubuntu
sudo apt-get update && sudo apt-get install stow

# Fedora
sudo dnf install stow

# Arch
sudo pacman -S stow
```

Then enable the dotfiles from the repository root:

```sh
cd ~/dotfiles
./startup.sh
```

The startup script is POSIX `sh` and works on both macOS and Linux. It checks
for GNU Stow, creates `~/.zsh_extra`, and stows this repository into `$HOME`.

To preview the links before changing anything:

```sh
./startup.sh --dry-run
```

## Testing

Run the Linux Docker smoke test from the repository root:

```sh
docker build -f tests/docker/Dockerfile -t dotfiles-startup-test tests/docker
docker run --rm -v "$PWD:/workspace:ro" dotfiles-startup-test
```

The image installs GNU Stow, then the container mounts this repository read-only,
runs `startup.sh --dry-run`, runs `startup.sh`, and verifies that the expected
dotfiles are linked. It also checks that Neovim is reachable through
`~/.config/nvim`, verifies key files such as `init.lua`, `lua/chadrc.lua`, and
`lazy-lock.json`, runs `nvim --headless +'quitall'` with isolated XDG
directories, and confirms repository-only files such as `README.md`,
`startup.sh`, `install.sh`, `.stow-local-ignore`, and `tests` are not linked
into `$HOME`.

Docker containers are Linux containers, so this does not provide a native macOS
runtime. For macOS, run `./startup.sh --dry-run` locally after installing GNU
Stow.

## Manual Stow setup

If you prefer to run the commands yourself:

```sh
cd ~/dotfiles
touch ~/.zsh_extra
stow --target="$HOME" --restow \
  --ignore='README.md' \
  --ignore='startup.sh' \
  --ignore='tests' \
  --ignore='.DS_Store' \
  --ignore='.claude' \
  .
```

`~/.zsh_extra` is intentionally left outside the repo. Put machine-specific
secrets, PATH additions, aliases, and local overrides there. The tracked
`.zshrc` sources it during shell startup.

If Stow reports conflicts, move or back up the existing target files first, then
run the command again. For example, if `~/.gitconfig` already exists as a normal
file:

```sh
mv ~/.gitconfig ~/.gitconfig.backup
./startup.sh
```

## Neovim configuration

The Neovim configuration lives at `.config/nvim` and is enabled when this repo
is stowed into `$HOME`. After setup, the expected runtime path is:

```text
~/.config/nvim -> ~/dotfiles/.config/nvim
```

This config is based on NvChad. Open Neovim after stowing to let the plugin
manager install the configured plugins:

```sh
nvim
```

If you already have a Neovim config, back it up before enabling these dotfiles:

```sh
mv ~/.config/nvim ~/.config/nvim.backup
cd ~/dotfiles
./startup.sh
```
