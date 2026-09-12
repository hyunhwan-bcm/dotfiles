#!/usr/bin/env bash
#
# tools/gh-pr-notify.sh — desktop notifications for GitHub pull request activity.
#
# Polls the GitHub notifications API through `gh` and posts one desktop
# notification per new or updated unread PR notification: a review request,
# a mention, a comment on your PR, CI activity, a merge/close. Clicking a
# notification opens the PR (or the comment) in the browser when
# terminal-notifier is installed.
#
# Usage
#   gh-pr-notify.sh            check once, notify what is new since last run
#   gh-pr-notify.sh --init     record the current state without notifying
#                              (this also happens automatically on the first run,
#                              so a fresh machine does not get a flood)
#   gh-pr-notify.sh --dry-run  print what would be notified, send nothing
#   gh-pr-notify.sh --list     print all matching unread notifications
#   gh-pr-notify.sh --test     send one sample notification to check the setup
#
# Settings (environment variables; put them in ~/.zsh_extra or the launchd plist)
#   GH_PR_NOTIFY_REASONS   comma list of GitHub notification reasons to report.
#                          default: review_requested,mention,team_mention,assign,
#                                   comment,author,ci_activity,state_change
#                          (`subscribed` is left out on purpose: it fires for
#                          every PR in every repo you watch)
#   GH_PR_NOTIFY_TYPES     comma list of subject types. default: PullRequest
#                          (add Issue to get issue notifications too)
#   GH_PR_NOTIFY_MAX       above this many new items, send ONE summary
#                          notification instead of one each. default: 5
#   GH_PR_NOTIFY_STATE     state directory.
#                          default: ${XDG_STATE_HOME:-~/.local/state}/gh-pr-notify
#
# Scheduling: on macOS install.sh loads tools/launchd/com.hyunhwan.dotfiles.gh-pr-notify.plist
# which runs this every 5 minutes. On Linux add a cron line such as
#   */5 * * * * $HOME/dotfiles/tools/gh-pr-notify.sh
#
# Requires: gh (logged in; the `repo` scope covers notifications), and one of
# terminal-notifier (macOS, clickable), osascript (macOS), notify-send (Linux).

set -euo pipefail

REASONS="${GH_PR_NOTIFY_REASONS:-review_requested,mention,team_mention,assign,comment,author,ci_activity,state_change}"
TYPES="${GH_PR_NOTIFY_TYPES:-PullRequest}"
MAX_INDIVIDUAL="${GH_PR_NOTIFY_MAX:-5}"
STATE_DIR="${GH_PR_NOTIFY_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/gh-pr-notify}"
SEEN_FILE="$STATE_DIR/seen"

mode="notify"
case "${1:-}" in
    --init)    mode="init" ;;
    --dry-run) mode="dry" ;;
    --list)    mode="list" ;;
    --test)    mode="test" ;;
    -h|--help) sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    "")        ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
esac

# ─── Notification back-ends ───────────────────────────────────────────────────

# notify <title> <subtitle> <message> <url>
#
# Back-ends are tried in order and the next one is used when the previous fails.
# terminal-notifier comes first because its notifications are clickable (-open
# opens the PR), but macOS can refuse it Notification Center access, in which
# case it exits non-zero and osascript takes over. osascript notifications
# inherit the permission of whatever launched the script, so they work out of
# the box, but they cannot carry a click action: the repo and PR number in the
# notification identify it, and `gh-pr-notify --list` prints the URLs.
notify() {
    local title="$1" subtitle="$2" message="$3" url="$4"

    if command -v terminal-notifier &>/dev/null; then
        if terminal-notifier -title "$title" -subtitle "$subtitle" -message "$message" \
                -open "$url" -group "gh-pr-notify:$url" >/dev/null 2>&1; then
            return 0
        fi
        hint_terminal_notifier
    fi

    if command -v osascript &>/dev/null; then
        # AppleScript string literals: escape backslashes, then double quotes.
        local t=${title//\\/\\\\} s=${subtitle//\\/\\\\} m=${message//\\/\\\\}
        t=${t//\"/\\\"}; s=${s//\"/\\\"}; m=${m//\"/\\\"}
        if osascript -e "display notification \"$m\" with title \"$t\" subtitle \"$s\"" 2>/dev/null; then
            return 0
        fi
    fi

    if command -v notify-send &>/dev/null; then
        notify-send --app-name=GitHub "$title — $subtitle" "$message
$url" && return 0
    fi

    echo "gh-pr-notify: no working notifier (terminal-notifier, osascript, notify-send)" >&2
    return 1
}

# Printed at most once a day, so a denied terminal-notifier does not spam the
# launchd log while still telling you how to get clickable notifications back.
hint_terminal_notifier() {
    local stamp="$STATE_DIR/tn-hint" today
    today="$(date +%Y-%m-%d)"
    [ -f "$stamp" ] && [ "$(cat "$stamp" 2>/dev/null)" = "$today" ] && return 0
    mkdir -p "$STATE_DIR" 2>/dev/null || true
    echo "$today" > "$stamp" 2>/dev/null || true
    echo "gh-pr-notify: terminal-notifier was refused by Notification Center; using osascript (no click-to-open)." >&2
    echo "  Fix: System Settings > Notifications > terminal-notifier > Allow Notifications." >&2
}

reason_label() {
    case "$1" in
        review_requested) echo "Review requested" ;;
        mention)          echo "You were mentioned" ;;
        team_mention)     echo "Your team was mentioned" ;;
        assign)           echo "Assigned to you" ;;
        comment)          echo "New comment" ;;
        author)           echo "Activity on your PR" ;;
        ci_activity)      echo "CI activity" ;;
        state_change)     echo "PR merged or closed" ;;
        subscribed)       echo "Update" ;;
        *)                echo "$1" ;;
    esac
}

# Turn the API URLs GitHub hands back into browser URLs.
#   .../repos/O/R/pulls/12                 -> https://github.com/O/R/pull/12
#   .../repos/O/R/issues/comments/99       -> <pr url>#issuecomment-99
#   .../repos/O/R/pulls/comments/99        -> <pr url>#discussion_r99
html_url() {
    local subject_url="$1" comment_url="$2" base
    base="${subject_url/https:\/\/api.github.com\/repos\//https://github.com/}"
    base="${base/\/pulls\//\/pull\/}"
    case "$comment_url" in
        */issues/comments/*) echo "$base#issuecomment-${comment_url##*/}" ;;
        */pulls/comments/*)  echo "$base#discussion_r${comment_url##*/}" ;;
        *)                   echo "$base" ;;
    esac
}

# ─── Test mode ────────────────────────────────────────────────────────────────

if [ "$mode" = "test" ]; then
    notify "gh-pr-notify · dotfiles" "Review requested" "#1 Sample notification — click to open GitHub" \
        "https://github.com/notifications"
    echo "sent a test notification"
    exit 0
fi

# ─── Fetch ────────────────────────────────────────────────────────────────────

if ! command -v gh &>/dev/null; then
    echo "gh-pr-notify: gh not found in PATH" >&2
    exit 1
fi

# jq runs inside gh, so jq itself is not required on the machine. `gh api --jq`
# has no --arg, so the two filter lists are spliced in as jq string literals;
# they are stripped to [a-z_,] first so nothing can escape the quotes.
safe_list() { printf '%s' "$1" | tr -cd 'a-zA-Z_,'; }
jq_filter='
    ("'"$(safe_list "$REASONS")"'" | split(",")) as $reasons
  | ("'"$(safe_list "$TYPES")"'"   | split(",")) as $types
  | .[]
  | select(.unread and (.reason as $r | $reasons | index($r)) and (.subject.type as $t | $types | index($t)))
  | [ .id, .updated_at, .reason, .repository.full_name, .subject.type,
      (.subject.title | gsub("[\\t\\n\\r]"; " ")),
      (.subject.url // ""), (.subject.latest_comment_url // "") ]
  | @tsv'

err_file="$(mktemp)"
trap 'rm -f "$err_file"' EXIT
if ! current="$(gh api notifications --paginate -X GET -F per_page=50 \
        --jq "$jq_filter" 2>"$err_file")"; then
    echo "gh-pr-notify: gh api failed: $(head -3 "$err_file")" >&2
    exit 1
fi

if [ "$mode" = "list" ]; then
    if [ -z "$current" ]; then echo "no unread notifications matching reasons=$REASONS types=$TYPES"; exit 0; fi
    while IFS=$'\t' read -r id updated reason repo type title surl curl_; do
        printf '%s  %-18s %-32s %s\n    %s\n' "${updated%Z}" "$(reason_label "$reason")" "$repo" "$title" "$(html_url "$surl" "$curl_")"
    done <<< "$current"
    exit 0
fi

# ─── Diff against last run ────────────────────────────────────────────────────

mkdir -p "$STATE_DIR"

first_run=0
if [ ! -f "$SEEN_FILE" ]; then
    first_run=1
fi

# New = id not seen before, or seen with an older updated_at.
new_items=""
if [ -n "$current" ] && [ "$first_run" -eq 0 ]; then
    new_items="$(awk -F'\t' 'NR==FNR { seen[$1]=$2; next }
                             !($1 in seen) || seen[$1] < $2' "$SEEN_FILE" - <<< "$current")"
fi

# Persist the state: keep every currently-unread id with its updated_at.
# Rewritten wholesale, so read/marked items drop out on their own.
printf '%s\n' "$current" | awk -F'\t' 'NF { print $1 "\t" $2 }' > "$SEEN_FILE.tmp"
mv "$SEEN_FILE.tmp" "$SEEN_FILE"

if [ "$mode" = "init" ] || [ "$first_run" -eq 1 ]; then
    n=0; [ -n "$current" ] && n=$(printf '%s\n' "$current" | grep -c .)
    echo "gh-pr-notify: recorded $n unread notification(s) as seen; nothing sent. Future runs notify only what is new."
    exit 0
fi

[ -z "$new_items" ] && exit 0

count=$(printf '%s\n' "$new_items" | grep -c .)

if [ "$mode" = "dry" ]; then
    echo "$count new:"
    while IFS=$'\t' read -r id updated reason repo type title surl curl_; do
        printf '  %-18s %-32s %s\n    %s\n' "$(reason_label "$reason")" "$repo" "$title" "$(html_url "$surl" "$curl_")"
    done <<< "$new_items"
    exit 0
fi

if [ "$count" -gt "$MAX_INDIVIDUAL" ]; then
    repos="$(printf '%s\n' "$new_items" | cut -f4 | sort | uniq -c | sort -rn | awk '{printf "%s%s (%d)", (NR>1?", ":""), $2, $1}')"
    notify "GitHub · $count PR updates" "Click to open your notifications" "$repos" \
        "https://github.com/notifications?query=is%3Aunread"
    exit 0
fi

while IFS=$'\t' read -r id updated reason repo type title surl curl_; do
    [ -z "$id" ] && continue
    number="${surl##*/}"
    # `|| true`: one failing notification must not abort the rest under set -e.
    notify "$repo" "$(reason_label "$reason")" "#$number $title" "$(html_url "$surl" "$curl_")" || true
done <<< "$new_items"
