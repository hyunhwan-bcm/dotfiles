# tools/check_for_update.zsh — keep ~/dotfiles current, the way oh-my-zsh does.
#
# Sourced from .zshrc on every interactive shell. Modeled on
# ohmyzsh/tools/check_for_upgrade.sh, adapted for a stow-managed dotfiles repo.
#
# How it works
#   1. A cheap epoch check decides whether it is time (default: once a day).
#   2. If so, the update runs in a BACKGROUND subshell after the first prompt,
#      so shell startup is never blocked by the network.
#   3. The result is printed at the next prompt: what was pulled, or why not.
#
# What the update does
#   git fetch, and if the branch is behind its upstream:
#   git pull --rebase with rebase.autoStash, so edits to tracked files (e.g.
#   nvim's lazy-lock.json) are stashed and re-applied instead of blocking the
#   update. Untracked files are ignored; they are normal here because
#   ~/.config is a symlink into this repo and apps drop state in it.
#   Then `install.sh --post-update` re-stows so new files get their symlinks.
#
# Settings (put in ~/.zsh_extra, before .zshrc sources this file is fine too)
#   zstyle ':dotfiles:update' mode auto        # auto (default) | reminder | disabled
#   zstyle ':dotfiles:update' frequency 1      # days between checks (default 1)
#   zstyle ':dotfiles:update' verbose default  # default | silent (no "up to date" noise either way)
#
# Manual: `dotfiles-update` (alias df-update) runs the update now, in the
# foreground, and prints the result.
#
# State lives in ${XDG_CACHE_HOME:-~/.cache}/dotfiles/update:
#   LAST_EPOCH=<days since 1970>  EXIT_STATUS=<n>  MESSAGE='...'

typeset -g DOTFILES_DIR="${DOTFILES_DIR:-$HOME/dotfiles}"
typeset -g DOTFILES_CACHE_DIR="${DOTFILES_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles}"

zmodload zsh/datetime
zmodload -F zsh/stat b:zstat

_dotfiles_epoch_days() { print -r -- $(( EPOCHSECONDS / 86400 )); }

# _dotfiles_write_state [exit_status] [message]
# With no arguments: record the check time only (clears any pending result).
_dotfiles_write_state() {
    local status_="${1:-}" msg="${2:-}"
    command mkdir -p "$DOTFILES_CACHE_DIR" 2>/dev/null || return 1
    if [[ -z "$status_" ]]; then
        print -r -- "LAST_EPOCH=$(_dotfiles_epoch_days)" >! "$DOTFILES_CACHE_DIR/update"
        return
    fi
    {
        print -r -- "LAST_EPOCH=$(_dotfiles_epoch_days)"
        print -r -- "EXIT_STATUS=$status_"
        print -r -- "MESSAGE='${msg//\'/\'\\\'\'}'"
    } >! "$DOTFILES_CACHE_DIR/update"
}

# _dotfiles_do_update <auto|reminder>
# Does the actual check/update and records the outcome in the state file.
# Safe to run in a background subshell. Returns 0 when nothing went wrong.
_dotfiles_do_update() {
    emulate -L zsh
    setopt no_unset pipe_fail
    local mode="${1:-auto}"
    local dir="$DOTFILES_DIR" lock="$DOTFILES_CACHE_DIR/update.lock"
    local mtime

    command mkdir -p "$DOTFILES_CACHE_DIR" 2>/dev/null || return 1

    # Lock, so two shells starting at once don't both pull. A lock older than
    # an hour is from a crashed run and is discarded.
    if mtime=$(zstat +mtime "$lock" 2>/dev/null) && (( mtime + 3600 < EPOCHSECONDS )); then
        command rm -rf "$lock"
    fi
    command mkdir "$lock" 2>/dev/null || return 0

    {
        if [[ ! -d "$dir/.git" ]]; then
            _dotfiles_write_state 1 "$dir is not a git checkout"
            return 1
        fi
        builtin cd -q "$dir" || return 1

        if [[ -d .git/rebase-merge || -d .git/rebase-apply || -f .git/MERGE_HEAD ]]; then
            _dotfiles_write_state 1 "a rebase or merge is in progress in $dir; finish it, then run dotfiles-update"
            return 1
        fi

        local branch upstream remote
        if ! branch=$(command git symbolic-ref --quiet --short HEAD 2>/dev/null); then
            _dotfiles_write_state 1 "$dir is on a detached HEAD; check out a branch, then run dotfiles-update"
            return 1
        fi
        if ! upstream=$(command git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null); then
            _dotfiles_write_state 1 "branch $branch in $dir has no upstream to update from"
            return 1
        fi
        remote="${upstream%%/*}"

        local err
        if ! err=$(LANG= command git fetch --quiet "$remote" 2>&1); then
            # Usually no network. Record the attempt so we don't retry on every
            # shell today, and stay quiet about it unless run by hand.
            _dotfiles_write_state 2 "fetch from $remote failed: ${err:-no details}"
            return 2
        fi

        local behind
        behind=$(command git rev-list --count "HEAD..$upstream" 2>/dev/null) || behind=0
        if (( behind == 0 )); then
            _dotfiles_write_state
            return 0
        fi

        if [[ "$mode" == reminder ]]; then
            _dotfiles_write_state 0 "$behind new commit(s) on $upstream. Run dotfiles-update to pull them."
            return 0
        fi

        local old new
        old=$(command git rev-parse --short HEAD)
        if ! err=$(LANG= command git -c rebase.autoStash=true pull --quiet --rebase "$remote" "$branch" 2>&1); then
            _dotfiles_write_state 1 "git pull --rebase failed in $dir:"$'\n'"${err}"
            return 1
        fi
        new=$(command git rev-parse --short HEAD)

        # New files (a plugin dir, a new .config/<app>) need their symlinks.
        if [[ -x "$dir/install.sh" ]]; then
            if ! err=$("$dir/install.sh" --post-update 2>&1); then
                _dotfiles_write_state 1 "updated $old..$new, but install.sh --post-update failed:"$'\n'"${err}"
                return 1
            fi
        fi

        _dotfiles_write_state 0 "updated $old..$new ($behind new commit(s)). Open a new shell to pick up changes."
        return 0
    } always {
        command rm -rf "$lock"
    }
}

# Print and clear a recorded result. Returns 1 if there was nothing to report.
_dotfiles_report_state() {
    local LAST_EPOCH EXIT_STATUS MESSAGE verbose
    source "$DOTFILES_CACHE_DIR/update" 2>/dev/null || return 1
    [[ -n "${EXIT_STATUS:-}" ]] || return 1
    zstyle -s ':dotfiles:update' verbose verbose || verbose=default

    if [[ "$EXIT_STATUS" == 0 ]]; then
        [[ "$verbose" == silent ]] || print -P "%F{green}[dotfiles]%f ${MESSAGE}"
    elif [[ "$EXIT_STATUS" == 2 ]]; then
        : # fetch failed (offline); not worth a message at every prompt
    else
        print -P "%F{red}[dotfiles]%f ${MESSAGE}"
    fi
    _dotfiles_write_state   # keep LAST_EPOCH, drop the result
    return 0
}

# User command: update now, in the foreground.
dotfiles-update() {
    emulate -L zsh
    local LAST_EPOCH EXIT_STATUS MESSAGE
    command rm -rf "$DOTFILES_CACHE_DIR/update.lock"
    print -P "%F{blue}[dotfiles]%f checking $DOTFILES_DIR …"
    _dotfiles_do_update auto
    source "$DOTFILES_CACHE_DIR/update" 2>/dev/null
    if [[ -z "${EXIT_STATUS:-}" ]]; then
        print -P "%F{green}[dotfiles]%f already up to date."
    elif [[ "$EXIT_STATUS" == 0 ]]; then
        print -P "%F{green}[dotfiles]%f ${MESSAGE}"
    else
        print -P "%F{red}[dotfiles]%f ${MESSAGE}"
    fi
    _dotfiles_write_state
    [[ "${EXIT_STATUS:-0}" == 0 ]]
}

# ─── Startup: decide whether to schedule a background check ──────────────────
() {
    emulate -L zsh
    local mode frequency LAST_EPOCH EXIT_STATUS MESSAGE

    zstyle -s ':dotfiles:update' mode mode || mode=auto
    [[ "$mode" != disabled ]] || return 0
    [[ -o interactive && -t 1 ]] || return 0
    [[ -d "$DOTFILES_DIR/.git" && -w "$DOTFILES_DIR" && -O "$DOTFILES_DIR" ]] || return 0
    (( ${+commands[git]} )) || return 0

    # A finished background run from a previous shell may still need reporting.
    if source "$DOTFILES_CACHE_DIR/update" 2>/dev/null && [[ -n "${EXIT_STATUS:-}" ]]; then
        _dotfiles_report_state
        return 0
    fi

    zstyle -s ':dotfiles:update' frequency frequency || frequency=1
    if [[ -n "${LAST_EPOCH:-}" ]] && (( $(_dotfiles_epoch_days) - LAST_EPOCH < frequency )); then
        return 0
    fi

    autoload -Uz add-zsh-hook
    typeset -g _dotfiles_update_mode="$mode" _dotfiles_update_started=0

    _dotfiles_bg_update() {
        # Fork after the first prompt so startup is not delayed.
        ( _dotfiles_do_update "$_dotfiles_update_mode" ) &|
        _dotfiles_update_started=$EPOCHSECONDS
        add-zsh-hook -d precmd _dotfiles_bg_update
        add-zsh-hook precmd _dotfiles_bg_update_status
        unset -f _dotfiles_bg_update
    }

    _dotfiles_bg_update_status() {
        local LAST_EPOCH EXIT_STATUS MESSAGE
        # Still running: the state file has no EXIT_STATUS yet and no fresh LAST_EPOCH.
        if source "$DOTFILES_CACHE_DIR/update" 2>/dev/null && [[ -n "${EXIT_STATUS:-}" ]]; then
            _dotfiles_report_state
        elif source "$DOTFILES_CACHE_DIR/update" 2>/dev/null \
             && [[ "${LAST_EPOCH:-}" == "$(_dotfiles_epoch_days)" ]] \
             && ! [[ -d "$DOTFILES_CACHE_DIR/update.lock" ]]; then
            : # finished quietly: already up to date
        elif (( EPOCHSECONDS - _dotfiles_update_started < 600 )); then
            return 0   # keep waiting
        fi
        add-zsh-hook -d precmd _dotfiles_bg_update_status
        unset -f _dotfiles_bg_update_status
        unset _dotfiles_update_mode _dotfiles_update_started
    }

    add-zsh-hook precmd _dotfiles_bg_update
}
