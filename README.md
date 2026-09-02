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

The script is **idempotent**: running it multiple times is safe.

## Files Managed

| File / Directory | Purpose |
|---|---|
| `.zshrc` | Zsh configuration (oh-my-zsh, plugins, aliases) |
| `.gitconfig` | Git settings |
| `.config/kitty/` | Kitty terminal settings |
| `.config/nvim/` | Neovim configuration |
| `.pi/agent/models.json` | Pi agent model config (file-level symlink, not stowed) |
| `.pi/agent/settings.json` | Pi agent settings (file-level symlink, not stowed) |
| `.ssh/config` | SSH client config: 1Password agent + tailnet hosts (file-level symlink, not stowed) |
| `.ssh/id_1password.pub` | Public half of the one SSH key kept in 1Password (file-level symlink, not stowed) |
| `bin/ssh-enroll-1password` | Pushes that public key to tailnet machines (repo-only, added to `PATH`) |

## SSH over Tailscale with one key in 1Password

Every machine on the tailnet is reachable by its MagicDNS name with the same
SSH key, and that key never leaves 1Password. The pieces:

- **`~/.ssh/config`** (tracked) selects the 1Password SSH agent when it is
  running locally, turns on agent forwarding and connection multiplexing for
  tailnet hosts, and maps bare names such as `studio` to their
  `*.tail5aee49.ts.net` address. Per-host login names live in the tailnet
  section; add a `Host` block there when a device joins.
- **`~/.ssh/config.local`** (untracked) is `Include`d first, so anything
  machine-specific or private goes there and wins. On first install an
  existing hand-written `~/.ssh/config` is moved to this file automatically.
- **`~/.ssh/id_1password.pub`** (tracked) is the public key. `install.sh` and
  `startup.sh` append it to `~/.ssh/authorized_keys`, so running the dotfiles
  on a machine is enough to let the 1Password key log in to it.
- **`.zshrc`** exports `SSH_AUTH_SOCK`: the 1Password socket on a desktop, or
  the forwarded agent (via a stable `~/.ssh/agent.sock` link) inside an SSH
  session, so hops between machines keep using the same key.

`~/.ssh` itself is never stowed; only those two files are symlinked.

To enrol machines that do not run these dotfiles yet, from a machine with
1Password unlocked:

```bash
ssh-enroll-1password                  # every online Linux/macOS tailnet peer
ssh-enroll-1password anjanda jani-spark
ssh-enroll-1password someone@mac-mini # override the login name for one host
```

It uses `ssh-copy-id`, so it authenticates however the host allows today
(existing key or password) and appends the 1Password key remotely.

Requirements on each desktop: 1Password with **Settings → Developer → Use the
SSH agent** enabled. On Linux servers nothing extra is needed; the agent is
forwarded from wherever you started.

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
