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
dotfiles are linked while repository-only files such as `README.md`,
`startup.sh`, and `tests` are not linked into `$HOME`.

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
run the command again. For example, if `~/.tmux.conf` already exists as a normal
file:

```sh
mv ~/.tmux.conf ~/.tmux.conf.backup
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
