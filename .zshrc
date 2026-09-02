# If you come from bash you might have to change your $PATH.
# export PATH=$HOME/bin:$HOME/.local/bin:/usr/local/bin:$PATH

# Path to your Oh My Zsh installation.
export ZSH="$HOME/.oh-my-zsh" # Set name of the theme to load --- if set to "random", it will
# load a random theme each time Oh My Zsh is loaded, in which case,
# to know which specific one was loaded, run: echo $RANDOM_THEME
# See https://github.com/ohmyzsh/ohmyzsh/wiki/Themes
ZSH_THEME="robbyrussell"

# Set list of themes to pick from when loading at random
# Setting this variable when ZSH_THEME=random will cause zsh to load
# a theme from this variable instead of looking in $ZSH/themes/
# If set to an empty array, this variable will have no effect.
# ZSH_THEME_RANDOM_CANDIDATES=( "robbyrussell" "agnoster" )

# Uncomment the following line to use case-sensitive completion.
# CASE_SENSITIVE="true"

# Uncomment the following line to use hyphen-insensitive completion.
# Case-sensitive completion must be off. _ and - will be interchangeable.
# HYPHEN_INSENSITIVE="true"

# Uncomment one of the following lines to change the auto-update behavior
# zstyle ':omz:update' mode disabled  # disable automatic updates
zstyle ':omz:update' mode auto      # update automatically without asking
# zstyle ':omz:update' mode reminder  # just remind me to update when it's time

# Uncomment the following line to change how often to auto-update (in days).
zstyle ':omz:update' frequency 13

# Uncomment the following line if pasting URLs and other text is messed up.
# DISABLE_MAGIC_FUNCTIONS="true"

# Uncomment the following line to disable colors in ls.
# DISABLE_LS_COLORS="true"

# Uncomment the following line to disable auto-setting terminal title.
# DISABLE_AUTO_TITLE="true"

# Uncomment the following line to enable command auto-correction.
# ENABLE_CORRECTION="true"

# Uncomment the following line to display red dots whilst waiting for completion.
# You can also set it to another string to have that shown instead of the default red dots.
# e.g. COMPLETION_WAITING_DOTS="%F{yellow}waiting...%f"
# Caution: this setting can cause issues with multiline prompts in zsh < 5.7.1 (see #5765)
COMPLETION_WAITING_DOTS="true"

# Uncomment the following line if you want to disable marking untracked files
# under VCS as dirty. This makes repository status check for large repositories
# much, much faster.
# DISABLE_UNTRACKED_FILES_DIRTY="true"

# Uncomment the following line if you want to change the command execution time
# stamp shown in the history command output.
# You can set one of the optional three formats:
# "mm/dd/yyyy"|"dd.mm.yyyy"|"yyyy-mm-dd"
# or set a custom format using the strftime function format specifications,
# see 'man strftime' for details.
# HIST_STAMPS="mm/dd/yyyy"

# Would you like to use another custom folder than $ZSH/custom?
# ZSH_CUSTOM=/path/to/new-custom-folder

# Which plugins would you like to load?
# Standard plugins can be found in $ZSH/plugins/
# Custom plugins may be added to $ZSH_CUSTOM/plugins/
# Example format: plugins=(rails git textmate ruby lighthouse)
# Add wisely, as too many plugins slow down shell startup.
plugins=(git)

source $ZSH/oh-my-zsh.sh
export LANG=en_US.UTF-8
[ -f "$HOME/.config/cache-paths.sh" ] && . "$HOME/.config/cache-paths.sh"

export EDITOR='nvim'
alias vi=nvim
alias vim=nvim
alias ls=eza
# fzf integration (--zsh requires fzf 0.48+; fall back for older versions)
if command -v fzf &>/dev/null; then
    if fzf --zsh &>/dev/null 2>&1; then
        source <(fzf --zsh)
    elif [ -f ~/.fzf.zsh ]; then
        source ~/.fzf.zsh
    fi
fi

oduck() {
    local n=10
    local file=""

    # --- Parse args for TTY (no stdin) case ---
    if [ -t 0 ]; then
        # Cases:
        #   oduck -100 file
        #   oduck file -100
        #   oduck file
        if [[ "$1" =~ ^-[0-9]+$ ]]; then
            n=${1:1}
            file="$2"
        elif [[ "$2" =~ ^-[0-9]+$ ]]; then
            n=${2:1}
            file="$1"
        else
            file="$1"
        fi

        if [ -z "$file" ]; then
            echo "Usage: oduck [-N] <file>"
            return 1
        fi

        duckdb -c "SELECT * FROM '$file' LIMIT $n;"
        return
    fi

    # --- Stdin case: oduck [-N], no filename ---
    # Example: cat file.parquet | oduck -50
    if [[ "$1" =~ ^-[0-9]+$ ]]; then
        n=${1:1}
    fi

    local tmpfile
    tmpfile=$(mktemp /tmp/oduck.XXXXXX)

    cat > "$tmpfile"
    duckdb -c "SELECT * FROM '$tmpfile' LIMIT $n;"
    rm "$tmpfile"
}

# -------------------------------
# dotfiles auto-update helper
# Silently checks for remote updates in ~/dotfiles on shell startup
# and pulls if the local branch is behind. Skips if there are
# uncommitted changes, merge conflicts, or no upstream configured.
# -------------------------------
dotfiles_update() {
    local repo_dir="$HOME/dotfiles"
    local stamp_file="$HOME/.dotfiles_update_stamp"

    # --- guard: skip if already checked within the last 24h ---
    if [ -f "$stamp_file" ]; then
        local age_seconds=$(( $(date +%s) - $(stat -f %m "$stamp_file" 2>/dev/null || echo 0) ))
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
        (cd "$repo_dir" && git pull -q --rebase origin "$(git rev-parse --abbrev-ref HEAD)" 2>/dev/null)
    fi

    # --- stamp: record check time ---
    touch "$stamp_file"
}

# convenience alias — forces a fresh check regardless of stamp
alias df-update='rm -f ~/.dotfiles_update_stamp; dotfiles_update'

# run silently on shell startup
# The function has a 24h stamp guard so it returns immediately if checked
# recently. Running synchronously avoids job control noise and the fact
# that nohup/setsid spawn /bin/sh which cannot find zsh functions (exit 127).
dotfiles_update >/dev/null 2>&1

# -------------------------------
# CLI freshness check (pi, claude, codex)
# On shell startup, at most once per day (24h stamp):
#   - missing CLI  → prompt with the install command (y/N)
#   - outdated CLI → auto-update silently (built-in updaters: pi update,
#     codex update, claude update)
# Prints a one-line summary. Runs synchronously (like dotfiles_update)
# so install prompts can use the terminal; the 24h stamp guard keeps
# normal logins fast.
# -------------------------------

# ver_gt A B → 0 if A > B (numeric dot-separated versions)
ver_gt() {
    local a b
    a=(${(s/./)1})
    b=(${(s/./)2})
    local i
    for i in 1 2 3; do
        (( ${a[i]:-0} > ${b[i]:-0} )) && return 0
        (( ${a[i]:-0} < ${b[i]:-0} )) && return 1
    done
    return 1
}

# Print the first semver found in $1
ver_extract() {
    printf '%s' "$1" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1
}

cli_freshness_check() {
    local stamp="$HOME/.cli_freshness_stamp"

    # --- guard: skip if already checked within the last 24h ---
    if [ -f "$stamp" ]; then
        local mtime
        mtime=$(stat -f %m "$stamp" 2>/dev/null || stat -c %Y "$stamp" 2>/dev/null || echo 0)
        [ $(( $(date +%s) - mtime )) -lt 86400 ] && return 0
    fi

    command -v npm >/dev/null 2>&1 || return 0

    local results=()
    local cur latest answer
    local npmview_opts=(--fetch-timeout=15000 --fetch-retries=1)

    # --- pi (@earendil-works/pi-coding-agent) ---
    if ! command -v pi >/dev/null 2>&1; then
        if [ -t 0 ]; then
            printf '[cli] pi is not installed.\n'
            printf '      Install with: npm install -g @earendil-works/pi-coding-agent\n'
            printf '      Install now? [y/N] '
            read -r answer
            case "$answer" in
                [yY]*) npm install -g @earendil-works/pi-coding-agent >/dev/null 2>&1 \
                    && results+=("pi: installed") || results+=("pi: install FAILED") ;;
                *) results+=("pi: MISSING (skipped)") ;;
            esac
        else
            results+=("pi: MISSING — npm install -g @earendil-works/pi-coding-agent")
        fi
    else
        cur=$(ver_extract "$(pi --version 2>/dev/null)")
        latest=$(npm view "${npmview_opts[@]}" @earendil-works/pi-coding-agent version 2>/dev/null)
        if [ -n "$latest" ] && [ -n "$cur" ] && ver_gt "$latest" "$cur" ]; then
            pi update >/dev/null 2>&1 \
                && results+=("pi: $cur → $latest") || results+=("pi: update FAILED (run: pi update)")
        else
            results+=("pi: $cur ✓")
        fi
    fi

    # --- codex (@openai/codex) ---
    if ! command -v codex >/dev/null 2>&1; then
        if [ -t 0 ]; then
            printf '[cli] codex is not installed.\n'
            printf '      Install with: npm install -g @openai/codex\n'
            printf '      Install now? [y/N] '
            read -r answer
            case "$answer" in
                [yY]*) npm install -g @openai/codex >/dev/null 2>&1 \
                    && results+=("codex: installed") || results+=("codex: install FAILED") ;;
                *) results+=("codex: MISSING (skipped)") ;;
            esac
        else
            results+=("codex: MISSING — npm install -g @openai/codex")
        fi
    else
        cur=$(ver_extract "$(codex --version 2>/dev/null)")
        latest=$(npm view "${npmview_opts[@]}" @openai/codex version 2>/dev/null)
        if [ -n "$latest" ] && [ -n "$cur" ] && ver_gt "$latest" "$cur" ]; then
            codex update >/dev/null 2>&1 \
                && results+=("codex: $cur → $latest") || results+=("codex: update FAILED (run: codex update)")
        else
            results+=("codex: $cur ✓")
        fi
    fi

    # --- claude (@anthropic-ai/claude-code, native installer) ---
    if ! command -v claude >/dev/null 2>&1; then
        if [ -t 0 ]; then
            printf '[cli] claude is not installed.\n'
            printf '      Install with: curl -fsSL https://claude.ai/install.sh | bash\n'
            printf '      Install now? [y/N] '
            read -r answer
            case "$answer" in
                [yY]*) curl -fsSL https://claude.ai/install.sh | bash >/dev/null 2>&1 \
                    && results+=("claude: installed") || results+=("claude: install FAILED") ;;
                *) results+=("claude: MISSING (skipped)") ;;
            esac
        else
            results+=("claude: MISSING — curl -fsSL https://claude.ai/install.sh | bash")
        fi
    else
        cur=$(ver_extract "$(claude --version 2>/dev/null)")
        latest=$(npm view "${npmview_opts[@]}" @anthropic-ai/claude-code version 2>/dev/null)
        if [ -n "$latest" ] && [ -n "$cur" ] && ver_gt "$latest" "$cur" ]; then
            claude update >/dev/null 2>&1 \
                && results+=("claude: $cur → $latest") || results+=("claude: update FAILED (run: claude update)")
        else
            results+=("claude: $cur ✓")
        fi
    fi

    touch "$stamp"
    local summary="" r
    for r in "${results[@]}"; do
        if [ -z "$summary" ]; then summary="$r"; else summary+=" | $r"; fi
    done
    printf '[cli] %s\n' "$summary"
}

# convenience alias — forces a fresh check regardless of stamp
alias cli-check='rm -f ~/.cli_freshness_stamp; cli_freshness_check'

# run on shell startup (24h stamp guard makes this a no-op most logins)
cli_freshness_check

# ── SSH: one 1Password key everywhere ────────────────────────────────────────
# Desktop with 1Password  → talk to its agent socket.
# Inside an SSH session   → keep the agent forwarded from the origin machine,
#                           but expose it at a stable path so shells that
#                           outlive the connection (tmux, screen) still find
#                           the current one after a reconnect.
if [ -n "$SSH_CONNECTION" ]; then
    _stable_sock="$HOME/.ssh/agent.sock"
    if [ -S "$SSH_AUTH_SOCK" ] && [ "$SSH_AUTH_SOCK" != "$_stable_sock" ]; then
        ln -sf "$SSH_AUTH_SOCK" "$_stable_sock"
    fi
    [ -S "$_stable_sock" ] && export SSH_AUTH_SOCK="$_stable_sock"
    unset _stable_sock
else
    for _sock in \
        "$HOME/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock" \
        "$HOME/.1password/agent.sock"; do
        if [ -S "$_sock" ]; then
            export SSH_AUTH_SOCK="$_sock"
            break
        fi
    done
    unset _sock
fi

# Repo-only helper scripts (bin/ is not stowed): ssh-enroll-1password, …
_dotfiles_bin="${${(%):-%x}:A:h}/bin"
[ -d "$_dotfiles_bin" ] && export PATH="$_dotfiles_bin:$PATH"
unset _dotfiles_bin

# Source ~/.zsh_extra for machine-specific configuration
# Add your local PATH additions, aliases, and settings there
[ -f "$HOME/.zsh_extra" ] && . "$HOME/.zsh_extra"

# Added by cua-driver-rs installer — see https://github.com/trycua/cua
export PATH="/Users/2katz/.local/bin:$PATH"
