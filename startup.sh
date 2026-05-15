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

if ! command -v stow >/dev/null 2>&1; then
  printf '%s\n' 'GNU Stow is required to enable these dotfiles.' >&2
  install_hint >&2
  exit 1
fi

if [ "$dry_run" -eq 1 ]; then
  printf '%s\n' 'DRY RUN: would ensure ~/.zsh_extra exists.'
  printf '%s\n' 'DRY RUN: would source ~/.bashrc if it exists.'
  stow --no --verbose \
    --dir="$script_dir" \
    --target="$HOME" \
    --restow \
    --ignore='README.md' \
    --ignore='startup.sh' \
    --ignore='tests' \
    --ignore='.DS_Store' \
    --ignore='.claude' \
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
    .
  printf '%s\n' 'Dotfiles are enabled.'
  if [ -f "$HOME/.bashrc" ]; then
    printf '%s\n' 'Sourcing ~/.bashrc...'
    . "$HOME/.bashrc"
  fi
fi
