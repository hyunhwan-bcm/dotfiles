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

assert_file_resolves_to_path() {
  path=$1
  expected=$2

  [ -f "$path" ] || fail "expected $path to be a file"
  resolved=$(resolve_path "$path")
  expected_resolved=$(resolve_path "$expected")
  [ "$resolved" = "$expected_resolved" ] || fail "expected $path to resolve to $expected_resolved, got $resolved"
}

assert_executable() {
  [ -x "$1" ] || fail "expected $1 to be executable"
}

assert_command() {
  command -v "$1" >/dev/null 2>&1 || fail "expected $1 to be installed"
}

step() {
  printf '==> %s\n' "$*"
}

step "repo: $repo"
step "home: $home"

step "checking startup.sh executable bit"
assert_executable "$repo/startup.sh"
assert_command git
assert_command nvim
assert_command cargo
assert_command node

step "running dry run"
"$repo/startup.sh" --dry-run >/tmp/startup-dry-run.log
assert_not_exists "$home/.zsh_extra"
assert_not_exists "$home/.zshrc"

step "seeding a hand-written ~/.ssh/config to check migration"
mkdir -p "$home/.ssh"
printf 'Host legacy\n  HostName legacy.example.com\n' > "$home/.ssh/config"
printf 'ssh-ed25519 AAAAexisting existing@key' > "$home/.ssh/authorized_keys"   # no trailing newline on purpose

step "running startup.sh"
"$repo/startup.sh" >/tmp/startup.log
assert_exists "$home/.zsh_extra"

step "checking core dotfile links"
assert_symlink_to_path "$home/.zshrc" "$repo/.zshrc"
assert_symlink_to_path "$home/.gitconfig" "$repo/.gitconfig"
assert_symlink_to_path "$home/.config" "$repo/.config"
assert_symlink_to_path "$home/alfred" "$repo/alfred"

step "checking ~/.ssh is a real directory with file-level links (never stowed)"
[ -d "$home/.ssh" ] && [ ! -L "$home/.ssh" ] || fail "expected $home/.ssh to be a real directory"
assert_symlink_to_path "$home/.ssh/config" "$repo/.ssh/config"
assert_symlink_to_path "$home/.ssh/id_1password.pub" "$repo/.ssh/id_1password.pub"
[ "$(stat -c %a "$home/.ssh")" = "700" ] || fail "expected $home/.ssh to be mode 700"

step "checking the hand-written ssh config moved to ~/.ssh/config.local"
assert_exists "$home/.ssh/config.local"
grep -q 'legacy.example.com' "$home/.ssh/config.local" || fail "expected legacy ssh config in config.local"
grep -q 'Include ~/.ssh/config.local' "$home/.ssh/config" || fail "expected tracked config to Include config.local"

step "checking the 1Password public key is authorized"
key_blob=$(awk '{ print $2 }' "$repo/.ssh/id_1password.pub")
grep -qF "$key_blob" "$home/.ssh/authorized_keys" || fail "expected 1Password key in authorized_keys"
grep -q '^ssh-ed25519 AAAAexisting existing@key$' "$home/.ssh/authorized_keys" || fail "expected pre-existing authorized key to survive intact"
[ "$(wc -l < "$home/.ssh/authorized_keys")" -eq 2 ] || fail "expected exactly 2 lines in authorized_keys"
[ "$(stat -c %a "$home/.ssh/authorized_keys")" = "600" ] || fail "expected authorized_keys to be mode 600"

step "checking Alfred preferences archive restoration"
assert_file_resolves_to_path \
  "$home/alfred/Alfred.alfredpreferences.tar.gz" \
  "$repo/alfred/Alfred.alfredpreferences.tar.gz"
assert_executable "$home/alfred/restore.sh"
"$home/alfred/restore.sh" "$home/alfred-restored" >/tmp/alfred-restore.log
assert_exists "$home/alfred-restored/Alfred.alfredpreferences/preferences/prefs.plist"
assert_exists "$home/alfred-restored/Alfred.alfredpreferences/preferences/workflows/prefs.plist"

step "checking Neovim config installed through ~/.config/nvim"
assert_file_resolves_to_path "$home/.config/nvim/init.lua" "$repo/.config/nvim/init.lua"
assert_file_resolves_to_path "$home/.config/nvim/lua/chadrc.lua" "$repo/.config/nvim/lua/chadrc.lua"
assert_file_resolves_to_path "$home/.config/nvim/lua/options.lua" "$repo/.config/nvim/lua/options.lua"
assert_file_resolves_to_path "$home/.config/nvim/lazy-lock.json" "$repo/.config/nvim/lazy-lock.json"

step "checking repository-only files are ignored"
assert_not_exists "$home/README.md"
assert_not_exists "$home/startup.sh"
assert_not_exists "$home/install.sh"
assert_not_exists "$home/.stow-local-ignore"
assert_not_exists "$home/.gitignore"
assert_not_exists "$home/tests"
assert_not_exists "$home/bin"

step "running startup.sh a second time"
"$repo/startup.sh" >/tmp/startup-second-run.log
assert_exists "$home/.zsh_extra"
assert_symlink_to_path "$home/.ssh/config" "$repo/.ssh/config"
[ "$(grep -cF "$key_blob" "$home/.ssh/authorized_keys")" -eq 1 ] || fail "expected authorized_keys entry not to be duplicated"
assert_not_exists "$home/.ssh/config.d"
assert_symlink_to_path "$home/.zshrc" "$repo/.zshrc"
assert_file_resolves_to_path "$home/.config/nvim/init.lua" "$repo/.config/nvim/init.lua"

step "checking ~/.zsh_extra behavior - should not overwrite existing file"
echo "# Custom machine-specific config" > "$home/.zsh_extra"
original_hash=$(md5sum "$home/.zsh_extra" | cut -d' ' -f1)
"$repo/startup.sh" >/tmp/startup-third-run.log
new_hash=$(md5sum "$home/.zsh_extra" | cut -d' ' -f1)
[ "$original_hash" = "$new_hash" ] || fail "expected ~/.zsh_extra to remain unchanged"

echo ""
echo "=== Manual Testing Required ==="
echo ""
echo "To test ~/.bashrc sourcing and machine-specific removal, run manually:"
echo ""
echo "1. Create ~/.bashrc with test content:"
echo "   echo 'echo test-bashrc' > ~/.bashrc"
echo ""
echo "2. Run startup.sh and check if ~/.bashrc is sourced in zsh:"
echo "   ./startup.sh"
echo ""
echo "3. Check ~/.zshrc does not contain machine-specific paths:"
echo "   grep -E '(antigravity|openclaw|LM Studio|HWAN-T7)' ~/.zshrc"
echo "   (should return nothing)"
echo ""
echo "4. Check ~/.zsh_extra has machine-specific paths:"
echo "   cat ~/.zsh_extra"
echo ""

step "checking Neovim headless startup exits without config errors"
rm -rf /tmp/dotfiles-nvim-repo /tmp/dotfiles-nvim-home /tmp/nvim-xdg
cp -R "$repo" /tmp/dotfiles-nvim-repo
mkdir -p /tmp/dotfiles-nvim-home /tmp/nvim-xdg/data /tmp/nvim-xdg/state /tmp/nvim-xdg/cache
HOME=/tmp/dotfiles-nvim-home /tmp/dotfiles-nvim-repo/startup.sh >/tmp/startup-nvim.log
HOME=/tmp/dotfiles-nvim-home \
  XDG_DATA_HOME=/tmp/nvim-xdg/data \
  XDG_STATE_HOME=/tmp/nvim-xdg/state \
  XDG_CACHE_HOME=/tmp/nvim-xdg/cache \
  nvim --headless +'quitall' >/tmp/nvim-headless.log 2>&1

if grep -E 'Error detected|Failed to run|stacktrace|module .* not found|E[0-9][0-9]*:' /tmp/nvim-headless.log >/dev/null 2>&1; then
  tail -100 /tmp/nvim-headless.log >&2
  fail "expected Neovim headless startup to complete without config errors"
fi

printf '%s\n' 'startup.sh Docker smoke test passed.'
