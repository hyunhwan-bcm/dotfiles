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
source ~/.zsh_extra

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

# run silently in background on shell startup
nohup dotfiles_update >/dev/null 2>&1 &
disown -h %+

# Added by Antigravity
export PATH="/Users/hyun-hwanjeong/.antigravity/antigravity/bin:$PATH"
# Docker CLI completions
[ -d "${DOCKER_CONFIG:-$HOME/.docker}/completions" ] && fpath=(${DOCKER_CONFIG:-$HOME/.docker}/completions $fpath)

# opencode
export PATH=$HOME/.opencode/bin:$PATH

fpath+=~/.zfunc

autoload -Uz compinit
compinit

[ -f "$HOME/.local/bin/env" ] && . "$HOME/.local/bin/env"
# Disable "You have new mail" notifications
unset MAILCHECK

# kitten ssh shortcut
alias kssh="kitten ssh"

# OpenClaw Completion (only if installed)
if [ -f "/Users/hyunhwan/.openclaw/completions/openclaw.zsh" ]; then
    source "/Users/hyunhwan/.openclaw/completions/openclaw.zsh"
fi

# Added by LM Studio CLI (lms)
export PATH="$PATH:/Users/hyun-hwanjeong/.cache/lm-studio/bin"
# End of LM Studio CLI section

# Offloaded caches to external drive (HWAN-T7)
if [ -d "/Volumes/HWAN-T7" ]; then
  export RUSTUP_HOME=/Volumes/HWAN-T7/cache/rustup
  export CARGO_HOME=/Volumes/HWAN-T7/cache/cargo
  export UV_CACHE_DIR=/Volumes/HWAN-T7/cache/uv
fi
