#!/usr/bin/env zsh
# Tests for tools/check_for_update.zsh (the dotfiles auto-updater).
# Runs inside the Dockerfile.update-test image; see README "Tests".
set -u

repo=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
home=${HOME:?}

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
pass() { printf 'PASS: %s\n' "$*"; }
step() { printf '\n==> %s\n' "$*"; }
assert_true()  { eval "$1"   || fail "expected '$1' to be true"; }
assert_false() { eval "! $1" || fail "expected '$1' to be false"; }

state_file() { cat "$DOTFILES_CACHE_DIR/update" 2>/dev/null; }
state_get()  { state_file | sed -n "s/^$1=//p" | sed "s/^'//; s/'\$//"; }
reset_state() { rm -rf "$DOTFILES_CACHE_DIR"; }
head_of() { git -C "$1" rev-parse --short HEAD; }
remote_commit() { # <file> <message>
    ( cd "$PUSHER" && echo "$2" > "$1" && git add "$1" && git commit -q -m "$2" && git push -q origin master )
}

# ---------------------------------------------------------------------------
# Setup: bare remote + clone standing in for ~/dotfiles, plus a pusher clone
# ---------------------------------------------------------------------------
step "Setting up test git repos"
REMOTE_BARE="$home/test_remote.git"
LOCAL_REPO="$home/dotfiles_test"
PUSHER="$home/pusher"
mkdir -p "$REMOTE_BARE" && git -C "$REMOTE_BARE" init -q --bare
git clone -q "$REMOTE_BARE" "$PUSHER"
( cd "$PUSHER" && git checkout -q -b master && echo '# dotfiles' > README.md && git add README.md \
  && git commit -q -m 'initial commit' && git push -q -u origin master )
git clone -q "$REMOTE_BARE" "$LOCAL_REPO"
# A tiny install.sh so the --post-update hook is exercised.
cat > "$PUSHER/install.sh" <<'SH'
#!/usr/bin/env bash
[ "${1:-}" = "--post-update" ] && { echo "post-update ran" > "$HOME/post_update_marker"; exit 0; }
SH
( cd "$PUSHER" && chmod +x install.sh && git add install.sh && git commit -q -m 'add install.sh' && git push -q origin master )
git -C "$LOCAL_REPO" pull -q --rebase origin master

export DOTFILES_DIR="$LOCAL_REPO"
export DOTFILES_CACHE_DIR="$home/.cache/dotfiles-test"
reset_state
# The startup block needs an interactive tty and bails otherwise; only the
# functions are under test here.
source "$repo/tools/check_for_update.zsh"
typeset -f _dotfiles_do_update >/dev/null || fail "functions not defined after sourcing"

# ---------------------------------------------------------------------------
step "TEST 1: up to date → no pull, LAST_EPOCH recorded, no EXIT_STATUS"
before=$(head_of "$LOCAL_REPO")
_dotfiles_do_update auto; rc=$?
assert_true "[ $rc -eq 0 ]"
assert_true "[ '$(head_of "$LOCAL_REPO")' = '$before' ]"
assert_true "[ -n '$(state_get LAST_EPOCH)' ]"
assert_true "[ -z '$(state_get EXIT_STATUS)' ]"
pass "TEST 1"

# ---------------------------------------------------------------------------
step "TEST 2: remote ahead → pulled, post-update hook ran, success message"
reset_state; rm -f "$home/post_update_marker"
remote_commit new_file.txt 'add new file on remote'
_dotfiles_do_update auto; rc=$?
assert_true "[ $rc -eq 0 ]"
assert_true "[ -f '$LOCAL_REPO/new_file.txt' ]"
assert_true "[ -f '$home/post_update_marker' ]"
assert_true "[ '$(state_get EXIT_STATUS)' = 0 ]"
assert_true "[[ '$(state_get MESSAGE)' == *'1 new commit'* ]]"
pass "TEST 2"

# ---------------------------------------------------------------------------
step "TEST 3: untracked files in the tree do not block the update"
reset_state
mkdir -p "$LOCAL_REPO/.config/someapp" && echo junk > "$LOCAL_REPO/.config/someapp/state"
remote_commit second.txt 'second remote commit'
_dotfiles_do_update auto
assert_true "[ -f '$LOCAL_REPO/second.txt' ]"
assert_true "[ -f '$LOCAL_REPO/.config/someapp/state' ]"
pass "TEST 3"

# ---------------------------------------------------------------------------
step "TEST 4: modified tracked file is autostashed and restored"
reset_state
echo 'local edit' >> "$LOCAL_REPO/README.md"
remote_commit third.txt 'third remote commit'
_dotfiles_do_update auto; rc=$?
assert_true "[ $rc -eq 0 ]"
assert_true "[ -f '$LOCAL_REPO/third.txt' ]"
assert_true "grep -q 'local edit' '$LOCAL_REPO/README.md'"
assert_true "[ -z \"\$(git -C '$LOCAL_REPO' stash list)\" ]"
git -C "$LOCAL_REPO" checkout -q -- README.md
pass "TEST 4"

# ---------------------------------------------------------------------------
step "TEST 5: conflicting local edit → pull fails, error recorded, repo left clean of rebase state"
reset_state
echo 'mine' > "$LOCAL_REPO/conflict.txt"
remote_commit conflict.txt 'theirs'
before=$(head_of "$LOCAL_REPO")
_dotfiles_do_update auto; rc=$?
assert_true "[ $rc -ne 0 ]"
assert_true "[ '$(state_get EXIT_STATUS)' = 1 ]"
assert_true "[[ '$(state_get MESSAGE)' == *'git pull --rebase failed'* ]]"
assert_false "[ -d '$LOCAL_REPO/.git/rebase-merge' ]"
# git aborts the pull when an untracked file would be overwritten; nothing moved.
assert_true "[ '$(head_of "$LOCAL_REPO")' = '$before' ]"
rm -f "$LOCAL_REPO/conflict.txt"; git -C "$LOCAL_REPO" pull -q --rebase origin master
pass "TEST 5"

# ---------------------------------------------------------------------------
step "TEST 6: reminder mode → no pull, message says how many commits"
reset_state
remote_commit fourth.txt 'fourth remote commit'
before=$(head_of "$LOCAL_REPO")
_dotfiles_do_update reminder
assert_true "[ '$(head_of "$LOCAL_REPO")' = '$before' ]"
assert_true "[ '$(state_get EXIT_STATUS)' = 0 ]"
assert_true "[[ '$(state_get MESSAGE)' == *'1 new commit'*'dotfiles-update'* ]]"
git -C "$LOCAL_REPO" pull -q --rebase origin master
pass "TEST 6"

# ---------------------------------------------------------------------------
step "TEST 7: in-progress rebase → refuses, explains"
reset_state
mkdir -p "$LOCAL_REPO/.git/rebase-merge"
_dotfiles_do_update auto; rc=$?
rmdir "$LOCAL_REPO/.git/rebase-merge"
assert_true "[ $rc -ne 0 ]"
assert_true "[[ '$(state_get MESSAGE)' == *'rebase or merge is in progress'* ]]"
pass "TEST 7"

# ---------------------------------------------------------------------------
step "TEST 8: no upstream → refuses, explains"
reset_state
git -C "$LOCAL_REPO" checkout -q -b local-only
_dotfiles_do_update auto; rc=$?
git -C "$LOCAL_REPO" checkout -q master; git -C "$LOCAL_REPO" branch -q -D local-only
assert_true "[ $rc -ne 0 ]"
assert_true "[[ '$(state_get MESSAGE)' == *'no upstream'* ]]"
pass "TEST 8"

# ---------------------------------------------------------------------------
step "TEST 9: fetch failure (remote gone) → EXIT_STATUS 2, LAST_EPOCH still recorded"
reset_state
mv "$REMOTE_BARE" "$REMOTE_BARE.away"
_dotfiles_do_update auto; rc=$?
mv "$REMOTE_BARE.away" "$REMOTE_BARE"
assert_true "[ $rc -eq 2 ]"
assert_true "[ '$(state_get EXIT_STATUS)' = 2 ]"
assert_true "[ -n '$(state_get LAST_EPOCH)' ]"
pass "TEST 9"

# ---------------------------------------------------------------------------
step "TEST 10: lock held by another run → this run does nothing and returns 0"
reset_state
mkdir -p "$DOTFILES_CACHE_DIR/update.lock"
remote_commit fifth.txt 'fifth remote commit'
before=$(head_of "$LOCAL_REPO")
_dotfiles_do_update auto; rc=$?
assert_true "[ $rc -eq 0 ]"
assert_true "[ '$(head_of "$LOCAL_REPO")' = '$before' ]"
assert_false "[ -f '$DOTFILES_CACHE_DIR/update' ]"
rmdir "$DOTFILES_CACHE_DIR/update.lock"
pass "TEST 10 (lock respected)"

step "TEST 11: stale lock (older than 1h) is discarded and the update proceeds"
mkdir -p "$DOTFILES_CACHE_DIR/update.lock"
touch -d '2 hours ago' "$DOTFILES_CACHE_DIR/update.lock" 2>/dev/null || touch -t "$(date -v-2H +%Y%m%d%H%M 2>/dev/null || date -d '2 hours ago' +%Y%m%d%H%M)" "$DOTFILES_CACHE_DIR/update.lock"
_dotfiles_do_update auto
assert_true "[ -f '$LOCAL_REPO/fifth.txt' ]"
assert_false "[ -d '$DOTFILES_CACHE_DIR/update.lock' ]"
pass "TEST 11"

# ---------------------------------------------------------------------------
step "TEST 12: dotfiles-update (foreground command) prints the result and clears it"
reset_state
remote_commit sixth.txt 'sixth remote commit'
out=$(dotfiles-update 2>&1)
assert_true "[[ '$out' == *'updated'*'1 new commit'* ]]"
assert_true "[ -z '$(state_get EXIT_STATUS)' ]"
out=$(dotfiles-update 2>&1)
assert_true "[[ '$out' == *'already up to date'* ]]"
pass "TEST 12"

# ---------------------------------------------------------------------------
step "TEST 13: missing repo → error recorded, non-zero, no crash"
reset_state
DOTFILES_DIR="$home/does-not-exist" _dotfiles_do_update auto; rc=$?
assert_true "[ $rc -ne 0 ]"
assert_true "[[ '$(state_get MESSAGE)' == *'not a git checkout'* ]]"
pass "TEST 13"

rm -rf "$REMOTE_BARE" "$LOCAL_REPO" "$PUSHER" "$DOTFILES_CACHE_DIR" "$home/post_update_marker"
printf '\nAll dotfiles auto-update tests passed.\n'
