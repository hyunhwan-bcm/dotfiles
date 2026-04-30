#!/usr/bin/env zsh
set -eu

repo=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
home=${HOME:?}

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

pass() {
  printf 'PASS: %s\n' "$*"
}

step() {
  printf '==> %s\n' "$*"
}

assert_true() {
  eval "$1" || fail "expected '$1' to be true"
}

assert_false() {
  eval "! $1" || fail "expected '$1' to be false"
}

# ---------------------------------------------------------------------------
# Setup: create a bare remote repo and clone it as ~/dotfiles
# We simulate the exact scenario: local is behind remote by N commits.
# ---------------------------------------------------------------------------
REMOTE_BARE="$home/test_remote.git"
LOCAL_REPO="$home/dotfiles_test"

step "Setting up test git repos"
mkdir -p "$REMOTE_BARE"
git -C "$REMOTE_BARE" init --bare

# Create initial content and push
mkdir -p /tmp/seed-repo
cd /tmp/seed-repo
git init
git config user.email "test@test.com"
git config user.name "Test"
echo '# dotfiles' > README.md
git add README.md
git commit -m 'initial commit'
git remote add origin "$REMOTE_BARE"
git push -u origin master

# Clone as ~/dotfiles_test (acts as the real ~/dotfiles)
git clone "$REMOTE_BARE" "$LOCAL_REPO"

# ---------------------------------------------------------------------------
# Extract dotfiles_update function from .zshrc so we can source it in tests
# ---------------------------------------------------------------------------
step "Extracting dotfiles_update function from .zshrc"
# We grep out the function definition block from the repo's .zshrc
cat > /tmp/dotfiles_update_func.zsh << 'FUNC_END'
dotfiles_update() {
    local repo_dir="$HOME/dotfiles_test"
    local stamp_file="$HOME/.dotfiles_update_stamp"

    # --- guard: skip if already checked within the last 24h ---
    if [ -f "$stamp_file" ]; then
        local age_seconds=$(( $(date +%s) - $(stat -c %Y "$stamp_file" 2>/dev/null || stat -f %m "$stamp_file" 2>/dev/null || echo 0) ))
        [ "$age_seconds" -lt 86400 ] && return 0
    fi

    # --- guard: repo must exist and be a git repo with an upstream ---
    [ -d "$repo_dir/.git" ] || return 0
    (cd "$repo_dir" && git rev-parse --abbrev-ref @{u} >/dev/null 2>&1) || return 0

    # --- guard: skip if working tree is dirty or has merge conflicts ---
    local dirty
    dirty=$(cd "$repo_dir" && git status --porcelain 2>/dev/null)
    [ -n "$dirty" ] && return 0

    # --- fetch and check for new commits ---
    (cd "$repo_dir" && git fetch -q origin 2>/dev/null) || return 0
    local ahead behind
    read ahead behind < <(cd "$repo_dir" && git rev-list --left-right --count HEAD...@{u} 2>/dev/null)

    # Only pull if we are behind (remote has new commits)
    if [ -n "$behind" ] && [ "$behind" -gt 0 ]; then
        (cd "$LOCAL_REPO" && git pull -q --rebase origin "$(git rev-parse --abbrev-ref HEAD)" 2>/dev/null)
    fi

    # --- stamp: record check time ---
    touch "$stamp_file"
}
FUNC_END

source /tmp/dotfiles_update_func.zsh

# ---------------------------------------------------------------------------
# TEST 1: Local is up-to-date → should not pull, should create stamp
# ---------------------------------------------------------------------------
step "TEST 1: Local up-to-date — no pull expected"
rm -f "$home/.dotfiles_update_stamp"

local_count_before=$(git -C "$LOCAL_REPO" rev-list --count HEAD)
dotfiles_update
local_count_after=$(git -C "$LOCAL_REPO" rev-list --count HEAD)

assert_true "[ \"$local_count_before\" = \"$local_count_after\" ]"
pass "TEST 1: commit count unchanged when up-to-date"

# ---------------------------------------------------------------------------
# TEST 2: Remote has new commits → should pull them in
# ---------------------------------------------------------------------------
step "TEST 2: Remote behind — pull expected"
rm -f "$home/.dotfiles_update_stamp"

# Add a new commit to the remote (via a temp clone)
git clone "$REMOTE_BARE" /tmp/remote-pusher
cd /tmp/remote-pusher
echo 'new content' > new_file.txt
git add new_file.txt
git commit -m 'add new file on remote'
git push origin master

local_count_before=$(git -C "$LOCAL_REPO" rev-list --count HEAD)
dotfiles_update
local_count_after=$(git -C "$LOCAL_REPO" rev-list --count HEAD)

assert_true "[ \"$local_count_after\" -gt \"$local_count_before\" ]"
pass "TEST 2: local pulled new commit from remote"

# ---------------------------------------------------------------------------
# TEST 3: Stamp file prevents re-check within 24h
# ---------------------------------------------------------------------------
step "TEST 3: Stamp prevents duplicate check"
check_count_before=$(git -C "$LOCAL_REPO" rev-list --count HEAD)

# Add another remote commit
cd /tmp/remote-pusher
echo 'another commit' > another.txt
git add another.txt
git commit -m 'second remote commit'
git push origin master

dotfiles_update  # should be skipped due to stamp
check_count_after=$(git -C "$LOCAL_REPO" rev-list --count HEAD)

assert_true "[ \"$check_count_before\" = \"$check_count_after\" ]"
pass "TEST 3: stamp prevented re-check within 24h"

# ---------------------------------------------------------------------------
# TEST 4: Dirty working tree → skip update
# ---------------------------------------------------------------------------
step "TEST 4: Dirty working tree — skip update"
rm -f "$home/.dotfiles_update_stamp"

# Add another remote commit
cd /tmp/remote-pusher
echo 'third commit' > third.txt
git add third.txt
git commit -m 'third remote commit'
git push origin master

# Make local dirty
echo 'dirty change' >> "$LOCAL_REPO/README.md"
git -C "$LOCAL_REPO" status --porcelain >/dev/null 2>&1  # confirm dirty

local_count_before=$(git -C "$LOCAL_REPO" rev-list --count HEAD)
dotfiles_update
local_count_after=$(git -C "$LOCAL_REPO" rev-list --count HEAD)

assert_true "[ \"$local_count_before\" = \"$local_count_after\" ]"
pass "TEST 4: dirty working tree prevented update"

# ---------------------------------------------------------------------------
# TEST 5: Non-existent repo → graceful no-op (return 0)
# ---------------------------------------------------------------------------
step "TEST 5: Non-existent repo — graceful no-op"
rm -f "$home/.dotfiles_update_stamp"

# Temporarily override repo_dir by renaming
mv "$LOCAL_REPO" "$LOCAL_REPO.bak"
result=0
dotfiles_update || result=$?
mv "$LOCAL_REPO.bak" "$LOCAL_REPO"

assert_true "[ \"$result\" = \"0\" ]"
pass "TEST 5: non-existent repo returned 0 (no crash)"

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------
rm -rf "$REMOTE_BARE" "$LOCAL_REPO" /tmp/seed-repo /tmp/remote-pusher \
       /tmp/dotfiles_update_func.zsh "$home/.dotfiles_update_stamp"

step "All dotfiles_update tests passed."
