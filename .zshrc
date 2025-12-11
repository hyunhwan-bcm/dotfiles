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

export EDITOR='nvim'
alias vi=nvim
alias vim=nvim
alias ls=eza
source <(fzf --zsh)
source ~/.zsh_extra

export CRUN_MODEL="gpt-5-mini"

crun() {
  if [ $# -eq 0 ]; then
    echo "Usage: crun <prompt>"
    return 1
  fi

  # Join all arguments into a prompt string
  local prompt="$*"

  copilot -p "$prompt" --model "$CRUN_MODEL" --allow-all-tools
}



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
# dotfiles update helper
# Checks for remote updates in $HOME/dotfiles and optionally pulls them
# -------------------------------
dotfiles_update() {
    local repo="$HOME/dotfiles"

    if [ ! -d "$repo/.git" ]; then
        echo "Not a git repository: $repo"
        return 1
    fi

    # fetch remote updates
    if ! git -C "$repo" fetch --prune --quiet; then
        echo "Failed to fetch updates from remote for $repo"
        return 1
    fi

    # current branch
    local branch
    branch=$(git -C "$repo" rev-parse --abbrev-ref HEAD 2>/dev/null) || branch=""
    if [ -z "$branch" ] || [ "$branch" = "HEAD" ]; then
        echo "Cannot determine current branch (detached HEAD?) in $repo"
        return 1
    fi

    # find upstream/tracking branch (fallback to origin/<branch>)
    local upstream
    upstream=$(git -C "$repo" rev-parse --abbrev-ref --symbolic-full-name "@{u}" 2>/dev/null) || upstream=""
    if [ -z "$upstream" ]; then
        if git -C "$repo" show-ref --verify --quiet "refs/remotes/origin/$branch"; then
            upstream="origin/$branch"
        else
            echo "No upstream/tracking branch found for $branch in $repo - cannot compare to remote."
            return 1
        fi
    fi

    # count commits local vs remote (left: local unique, right: remote unique)
    local counts
    counts=$(git -C "$repo" rev-list --left-right --count "$branch...$upstream" 2>/dev/null)
    if [ -z "$counts" ]; then
        echo "Unable to compute commit counts between local ($branch) and $upstream for $repo"
        return 1
    fi
    set -- $counts
    local ahead=$1
    local behind=$2

    if [ "$behind" -eq 0 ]; then
        echo "Your $repo is up-to-date with $upstream (no new commits)."
        return 0
    fi

    echo "Found $behind new commit(s) on $upstream (remote). You're ahead by $ahead commit(s)."

    if [ "$ahead" -gt 0 ] && [ "$behind" -gt 0 ]; then
        echo "Local and remote have diverged. Please merge or rebase manually:"
        echo "  cd $repo && git fetch && git log --oneline --graph --decorate --all"
        return 1
    fi

    echo "New commits on $upstream (from oldest to newest):"
    git -C "$repo" log --oneline --decorate --reverse "$branch..$upstream"

    local ans
    read -r -p "Pull updates into $repo? [y/N] " ans
    case "$ans" in
        y|Y)
            # ensure there are no uncommitted or untracked changes
            if [ -n "$(git -C "$repo" status --porcelain 2>/dev/null)" ]; then
                echo "You have uncommitted or untracked changes in $repo. Please commit/stash them before pulling."
                echo "  cd $repo && git status --porcelain"
                return 1
            fi

            # attempt a fast-forward pull first
            if git -C "$repo" pull --ff-only; then
                echo "Pull complete."
                return 0
            else
                echo "Fast-forward pull failed; attempting regular pull (may create merge commits)..."
                if git -C "$repo" pull; then
                    echo "Pull complete."
                    return 0
                else
                    echo "Pull failed; please update $repo manually."
                    return 1
                fi
            fi
            ;;
        *)
            echo "Not pulling."
            return 0
            ;;
    esac
}

# convenience aliases
alias df-update='dotfiles_update'

df-update

