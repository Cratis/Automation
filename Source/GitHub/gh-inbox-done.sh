#!/usr/bin/env bash
#
# gh-inbox-done.sh — mark GitHub notifications as "done" once they're moot.
#
# GitHub's notification inbox never cleans itself up: a PR notification stays
# in your inbox even after the PR is merged, and an issue notification stays
# even after the issue is closed. This script sweeps your notifications and
# marks any thread pointing at a merged pull request or a closed issue as
# "done" — the same action as clicking the checkmark in the web inbox — so
# what's left is only things that still need your attention.
#
# By default a pull request is marked done when it is either merged OR closed
# without merging — both mean no further action is needed from you. Pass
# --merged-only to leave closed-but-unmerged PRs alone.
#
# Notification types other than Issue and PullRequest (releases, discussions,
# commits, workflow runs, Copilot agent sessions, ...) are left untouched —
# this script only knows how to judge issues and pull requests as "done".
#
# Usage:
#   ./gh-inbox-done.sh                  # sweep all notifications (read + unread)
#   ./gh-inbox-done.sh --dry-run        # show what would be marked done
#   ./gh-inbox-done.sh --unread-only    # only look at currently-unread notifications
#   ./gh-inbox-done.sh --merged-only    # closed-without-merge PRs are left alone
#   ./gh-inbox-done.sh --verbose        # also print what was left alone, and why
#   ./gh-inbox-done.sh --jobs 8         # parallel API calls (default 4)
#
# Requirements: gh >= 2.0 (https://cli.github.com), authenticated via
# `gh auth login`. Token scopes: `notifications` or `repo` (either satisfies
# the notifications API; `repo` is what gh-subscribe.sh already needs).
#
# Marking a thread "done" is reversible — it just leaves the default inbox
# view; the thread is still visible via the "is:done" filter on
# https://github.com/notifications and can be marked unread again from there.

set -euo pipefail

JOBS="${GH_INBOX_DONE_JOBS:-4}"
DRY_RUN=false
UNREAD_ONLY=false
MERGED_ONLY=false
VERBOSE=false

usage() { sed -n '2,34p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

while [ $# -gt 0 ]; do
    case "$1" in
        -n|--dry-run)     DRY_RUN=true; shift ;;
        --unread-only)    UNREAD_ONLY=true; shift ;;
        --merged-only)    MERGED_ONLY=true; shift ;;
        -v|--verbose)     VERBOSE=true; shift ;;
        --jobs)           JOBS="${2:?--jobs needs a value}"; shift 2 ;;
        --jobs=*)         JOBS="${1#*=}"; shift ;;
        -h|--help)        usage 0 ;;
        *)                printf 'unknown option: %s\n\n' "$1" >&2; usage 1 ;;
    esac
done

# ----------------------------------------------------------------- output ---

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    BOLD=$(printf '\033[1m'); DIM=$(printf '\033[2m'); RED=$(printf '\033[31m')
    GREEN=$(printf '\033[32m'); RESET=$(printf '\033[0m')
else
    BOLD=""; DIM=""; RED=""; GREEN=""; RESET=""
fi

info()  { printf '%s\n' "$*"; }
head1() { printf '\n%s%s%s\n' "$BOLD" "$*" "$RESET"; }
ok()    { printf '  %s✓%s %s\n' "$GREEN" "$RESET" "$*"; }
fail()  { printf '  %s✗%s %s\n' "$RED" "$RESET" "$*"; }
note()  { printf '  %s%s%s\n' "$DIM" "$*" "$RESET"; }
die()   { printf '%serror:%s %s\n' "$RED" "$RESET" "$*" >&2; exit 1; }

TMP=$(mktemp -d "${TMPDIR:-/tmp}/gh-inbox-done.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
TAB=$(printf '\t')

# -------------------------------------------------------------- preflight ---

command -v gh >/dev/null 2>&1 || die "gh is not installed — see https://cli.github.com"
gh auth status >/dev/null 2>&1 || die "not logged in — run: gh auth login"

read_scopes() {
    gh api -i user 2>/dev/null | tr -d '\r' \
        | awk 'tolower($1) == "x-oauth-scopes:" { $1=""; print }' | tr -d ' '
}
SCOPES=$(read_scopes)
has_scope() { case ",$SCOPES," in *",$1,"*) return 0 ;; *) return 1 ;; esac; }

if ! has_scope notifications && ! has_scope repo; then
    die "missing 'notifications' (or 'repo') scope — add one with: gh auth refresh -h github.com -s notifications"
fi

head1 "GitHub inbox cleanup"
if $UNREAD_ONLY; then note "scope: unread notifications only"; else note "scope: all notifications (read + unread)"; fi
if $MERGED_ONLY; then note "pull requests: only mark done when merged"; else note "pull requests: mark done when merged or closed"; fi
$DRY_RUN && note "dry run — no changes will be made"

# -------------------------------------------------------------- fetch ---

ALL_PARAM="true"
$UNREAD_ONLY && ALL_PARAM="false"

gh api -X GET notifications --paginate -f "all=${ALL_PARAM}" -f "per_page=100" \
    --jq '.[] | [.id, .subject.type, (.subject.url // ""), .repository.full_name, .subject.title] | @tsv' \
    > "$TMP/notifications" 2>"$TMP/err" || die "could not list notifications: $(cat "$TMP/err")"

TOTAL=$(wc -l < "$TMP/notifications" | tr -d ' ')
note "fetched ${TOTAL} notifications"

if [ "$TOTAL" -eq 0 ]; then
    head1 "Nothing to do — inbox is empty."
    exit 0
fi

# ---------------------------------------------------------- classify ---

# For one notification line, decide whether its subject (issue or PR) is
# resolved, and print "done:<id>:<repo>#<num>:<title>" or "skip:<reason>:...".
classify() {
    _id="$1"; _type="$2"; _url="$3"; _repo="$4"; _title="$5"

    case "$_type" in
        Issue|PullRequest) ;;
        *) printf 'skip:type(%s):%s:%s: %s\n' "$_type" "$_id" "$_repo" "$_title"; return ;;
    esac

    [ -n "$_url" ] || { printf 'skip:no-url:%s:%s: %s\n' "$_id" "$_repo" "$_title"; return; }

    _path="${_url#https://api.github.com/}"
    _resource=$(gh api "$_path" --jq '"\(.state)\t\(.merged // false)"' 2>/dev/null) || {
        printf 'skip:fetch-failed:%s:%s: %s\n' "$_id" "$_repo" "$_title"; return
    }
    IFS="$(printf '\t')" read -r _state _merged <<< "$_resource"

    case "$_type" in
        Issue)
            if [ "$_state" = "closed" ]; then
                printf 'done:%s:%s:%s\n' "$_id" "$_repo" "$_title"
            else
                printf 'skip:open:%s:%s: %s\n' "$_id" "$_repo" "$_title"
            fi
            ;;
        PullRequest)
            if [ "$_merged" = "true" ]; then
                printf 'done:%s:%s:%s\n' "$_id" "$_repo" "$_title"
            elif [ "$_state" = "closed" ] && ! $MERGED_ONLY; then
                printf 'done:%s:%s:%s\n' "$_id" "$_repo" "$_title"
            else
                printf 'skip:open:%s:%s: %s\n' "$_id" "$_repo" "$_title"
            fi
            ;;
    esac
}
# Run classify() over every notification with up to $JOBS in flight. Deliberately
# not xargs -I{}: that splices each line's text (including the issue/PR title —
# free-form text set by whoever opened it) straight into a shell command string,
# which is a command-injection footgun. Backgrounding the function directly keeps
# every field a plain argv value that is never re-parsed as shell syntax.
: > "$TMP/classified"
RUNNING=0
while IFS="$TAB" read -r id type url repo title; do
    [ -n "$id" ] || continue
    classify "$id" "$type" "$url" "$repo" "$title" >> "$TMP/classified" &
    RUNNING=$((RUNNING + 1))
    if [ "$RUNNING" -ge "$JOBS" ]; then
        wait
        RUNNING=0
    fi
done < "$TMP/notifications"
wait

# ------------------------------------------------------------- act ---

DONE=0; SKIPPED=0; FAILED=0

grep '^done:' "$TMP/classified" > "$TMP/todo" || : > "$TMP/todo"
TODO_COUNT=$(wc -l < "$TMP/todo" | tr -d ' ')

head1 "Resolved (merged / closed)"
if [ "$TODO_COUNT" -eq 0 ]; then
    note "none found"
else
    if $DRY_RUN; then
        while IFS=':' read -r _ id repo title; do
            note "would mark done: ${repo} — ${title}"
        done < "$TMP/todo"
        DONE=$TODO_COUNT
    else
        # Notification thread ids are always decimal digit strings from GitHub's
        # own API — the grep is a defensive belt-and-suspenders check, not a
        # workaround for anything observed. $0 (not text substitution) is what
        # keeps this safe even if that ever stopped being true.
        cut -d: -f2 "$TMP/todo" | grep -E '^[0-9]+$' > "$TMP/todo-ids" || : > "$TMP/todo-ids"
        # shellcheck disable=SC2016  # $0 is expanded by the inner bash -c, not this shell
        xargs -P "$JOBS" -n1 bash -c '
            if gh api -X DELETE "notifications/threads/$0" --silent >/dev/null 2>&1
            then echo "ok $0"; else echo "fail $0"; fi
        ' < "$TMP/todo-ids" > "$TMP/results" || true

        while IFS=' ' read -r status id; do
            _line=$(grep "^done:${id}:" "$TMP/todo" | head -1)
            _repo=$(printf '%s' "$_line" | cut -d: -f3)
            _title=$(printf '%s' "$_line" | cut -d: -f4-)
            case "$status" in
                ok)   ok "${_repo} — ${_title}"; DONE=$((DONE + 1)) ;;
                fail) fail "${_repo} — thread ${id}"; FAILED=$((FAILED + 1)) ;;
            esac
        done < "$TMP/results"
    fi
fi

SKIPPED=$(grep -c '^skip:' "$TMP/classified" || true)

if $VERBOSE && [ "$SKIPPED" -gt 0 ]; then
    head1 "Left alone"
    while IFS=':' read -r _ reason id repo title; do
        note "${repo} — ${title} (${reason})"
    done < <(grep '^skip:' "$TMP/classified")
fi

# ---------------------------------------------------------------- summary ---

head1 "Summary"
if $DRY_RUN; then
    info "  ${DONE} would be marked done, ${SKIPPED} left alone (still open, or not an issue/PR)"
    printf '\n'
    note "Dry run — nothing was changed. Re-run without --dry-run to apply."
else
    info "  ${DONE} marked done, ${SKIPPED} left alone, ${FAILED} failed"
fi

[ "$FAILED" -eq 0 ]
