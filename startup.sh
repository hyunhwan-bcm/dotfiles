#!/usr/bin/env sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
dry_run=0

if [ "${1:-}" = "--dry-run" ] || [ "${1:-}" = "-n" ]; then
  dry_run=1
fi

install_hint() {
  case "$(uname -s)" in
    Darwin)
      printf '%s\n' 'Install it with: brew install stow'
      ;;
    Linux)
      if command -v apt-get >/dev/null 2>&1; then
        printf '%s\n' 'Install it with: sudo apt-get update && sudo apt-get install stow'
      elif command -v dnf >/dev/null 2>&1; then
        printf '%s\n' 'Install it with: sudo dnf install stow'
      elif command -v pacman >/dev/null 2>&1; then
        printf '%s\n' 'Install it with: sudo pacman -S stow'
      else
        printf '%s\n' 'Install GNU Stow with your Linux distribution package manager.'
      fi
      ;;
    *)
      printf '%s\n' 'Install GNU Stow with your operating system package manager.'
      ;;
  esac
}

# ~/.ssh is never stowed (that would drag private keys into the repo). Only
# the tracked config and the 1Password public key are linked, file by file,
# and the public key is authorized for logins to this machine.
link_ssh_files() {
  ssh_dir="$HOME/.ssh"
  if [ -L "$ssh_dir" ]; then
    printf '%s\n' "$ssh_dir is a symlink; it must be a real directory." >&2
    exit 1
  fi
  mkdir -p "$ssh_dir"
  chmod 700 "$ssh_dir"

  # A hand-written ~/.ssh/config becomes ~/.ssh/config.local, which the
  # tracked config Includes first (so its entries keep winning).
  if [ -f "$ssh_dir/config" ] && [ ! -L "$ssh_dir/config" ]; then
    dest="$ssh_dir/config.local"
    if [ -e "$dest" ]; then
      mkdir -p "$ssh_dir/config.d"
      dest="$ssh_dir/config.d/migrated-$(date +%Y%m%d%H%M%S)"
    fi
    printf 'Moving unmanaged %s -> %s\n' "$ssh_dir/config" "$dest"
    mv "$ssh_dir/config" "$dest"
  fi
  [ -e "$ssh_dir/config.local" ] || : > "$ssh_dir/config.local"

  for file in config id_1password.pub; do
    src="$script_dir/.ssh/$file"
    dst="$ssh_dir/$file"
    [ -f "$src" ] || continue
    if [ -L "$dst" ]; then
      rm "$dst"
    elif [ -e "$dst" ]; then
      mv "$dst" "$dst.bak.$(date +%Y%m%d%H%M%S)"
    fi
    ln -s "$src" "$dst"
  done

  pub="$script_dir/.ssh/id_1password.pub"
  ak="$ssh_dir/authorized_keys"
  [ -f "$pub" ] || return 0
  blob=$(awk '{ print $2 }' "$pub")
  touch "$ak"
  chmod 600 "$ak"
  if ! grep -qF -- "$blob" "$ak"; then
    if [ -s "$ak" ] && [ -n "$(tail -c1 "$ak")" ]; then
      echo >> "$ak"
    fi
    cat "$pub" >> "$ak"
  fi
}

if ! command -v stow >/dev/null 2>&1; then
  printf '%s\n' 'GNU Stow is required to enable these dotfiles.' >&2
  install_hint >&2
  exit 1
fi

if [ "$dry_run" -eq 1 ]; then
  printf '%s\n' 'DRY RUN: would ensure ~/.zsh_extra exists.'
  printf '%s\n' 'DRY RUN: would source ~/.bashrc if it exists.'
  printf '%s\n' 'DRY RUN: would link ~/.ssh/config and ~/.ssh/id_1password.pub and authorize the 1Password key.'
  stow --no --verbose \
    --dir="$script_dir" \
    --target="$HOME" \
    --restow \
    --ignore='README.md' \
    --ignore='startup.sh' \
    --ignore='tests' \
    --ignore='.DS_Store' \
    --ignore='.claude' \
    --ignore='.pi' \
    --ignore='.ssh' \
    --ignore='bin' \
    .
  printf '%s\n' 'Dry run complete.'
else
  touch "$HOME/.zsh_extra"
  stow \
    --dir="$script_dir" \
    --target="$HOME" \
    --restow \
    --ignore='README.md' \
    --ignore='startup.sh' \
    --ignore='tests' \
    --ignore='.DS_Store' \
    --ignore='.claude' \
    --ignore='.pi' \
    --ignore='.ssh' \
    --ignore='bin' \
    .
  link_ssh_files
  printf '%s\n' 'Dotfiles are enabled.'
  if [ -f "$HOME/.bashrc" ]; then
    printf '%s\n' 'Sourcing ~/.bashrc...'
    . "$HOME/.bashrc"
  fi
fi
