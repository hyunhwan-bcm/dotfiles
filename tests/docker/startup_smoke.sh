#!/usr/bin/env sh
set -eu

repo=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
home=${HOME:?}

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_exists() {
  [ -e "$1" ] || fail "expected $1 to exist"
}

assert_not_exists() {
  [ ! -e "$1" ] || fail "expected $1 not to exist"
}

resolve_link_target() {
  path=$1
  target=$2

  case "$target" in
    /*)
      printf '%s\n' "$target"
      ;;
    *)
      link_dir=$(CDPATH= cd -- "$(dirname -- "$path")" && pwd -P)
      target_dir=$(CDPATH= cd -- "$link_dir/$(dirname -- "$target")" && pwd -P)
      printf '%s/%s\n' "$target_dir" "$(basename -- "$target")"
      ;;
  esac
}

resolve_path() {
  path=$1

  path_dir=$(CDPATH= cd -- "$(dirname -- "$path")" && pwd -P)
  printf '%s/%s\n' "$path_dir" "$(basename -- "$path")"
}

assert_symlink_to_path() {
  path=$1
  expected=$2

  [ -L "$path" ] || fail "expected $path to be a symlink"
  target=$(readlink "$path")
  resolved=$(resolve_link_target "$path" "$target")
  expected_resolved=$(resolve_path "$expected")
  [ "$resolved" = "$expected_resolved" ] || fail "expected $path to resolve to $expected_resolved, got $resolved"
}

assert_executable() {
  [ -x "$1" ] || fail "expected $1 to be executable"
}

step() {
  printf '==> %s\n' "$*"
}

step "repo: $repo"
step "home: $home"

step "checking startup.sh executable bit"
assert_executable "$repo/startup.sh"

step "running dry run"
"$repo/startup.sh" --dry-run >/tmp/startup-dry-run.log
assert_not_exists "$home/.zsh_extra"
assert_not_exists "$home/.zshrc"

step "running startup.sh"
"$repo/startup.sh" >/tmp/startup.log
assert_exists "$home/.zsh_extra"
assert_symlink_to_path "$home/.zshrc" "$repo/.zshrc"
assert_symlink_to_path "$home/.tmux.conf" "$repo/.tmux.conf"
assert_symlink_to_path "$home/.gitconfig" "$repo/.gitconfig"
assert_symlink_to_path "$home/.config" "$repo/.config"
assert_not_exists "$home/README.md"
assert_not_exists "$home/startup.sh"
assert_not_exists "$home/tests"

step "running startup.sh a second time"
"$repo/startup.sh" >/tmp/startup-second-run.log
assert_exists "$home/.zsh_extra"
assert_symlink_to_path "$home/.zshrc" "$repo/.zshrc"

printf '%s\n' 'startup.sh Docker smoke test passed.'
