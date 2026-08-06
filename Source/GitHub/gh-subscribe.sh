#!/usr/bin/env bash
#
# gh-subscribe.sh — reconcile your GitHub notification subscriptions for an org.
#
# Every repository in the org is driven to one of two explicit states:
#
#   watch   subscribed to all activity                  (the default)
#   ignore  actively muted — no notifications at all, not even @mentions
#
# Ignoring is deliberately stronger than simply not watching: an unwatched repo
# still notifies you when you are mentioned or participate, a muted one never
# does. Archived repositories and forks are muted by default; add your own with
# --ignore.
#
# It also follows every member of the org, so their activity reaches you.
#
# The script is idempotent: it reads your current state first and only issues
# writes for what is actually wrong. Running it twice is a no-op.
#
# Usage:
#   ./gh-subscribe.sh                          # apply to the default orgs
#   ./gh-subscribe.sh --dry-run                # show what would change, write nothing
#   ./gh-subscribe.sh --orgs Cratis,Dolittle   # override the org list
#   ./gh-subscribe.sh --ignore 'Samples,*.github.io'   # mute these too
#   ./gh-subscribe.sh --no-follow              # only watch repos, don't follow people
#   ./gh-subscribe.sh --no-watch               # only follow people, don't watch repos
#   ./gh-subscribe.sh --include-archived       # watch archived repos instead of muting
#   ./gh-subscribe.sh --include-forks          # watch forks instead of muting
#   ./gh-subscribe.sh --no-default-ignores     # leave archived/forks alone entirely
#   ./gh-subscribe.sh --unwatch                # reverse: drop all subscriptions
#
# Ignore patterns are shell globs, matched case-insensitively against both the
# repository name (`Samples`) and its full name (`Cratis/Samples`).
#
# Environment:
#   GH_SUBSCRIBE_ORGS     comma-separated default org list
#   GH_SUBSCRIBE_IGNORE   comma-separated default ignore patterns
#   GH_SUBSCRIBE_JOBS     parallel API calls (default 4)
#
# Requirements: gh >= 2.0 (https://cli.github.com), authenticated via `gh auth login`.
# Token scopes: `repo` (watching) and `read:org` + `user:follow` (following).
#
# NOTE: this controls *what generates notifications*, not *how they reach you*.
# GitHub exposes no API for email delivery preferences — tick the Email boxes once
# at https://github.com/settings/notifications and this script handles the rest.

set -euo pipefail

DEFAULT_ORGS="Cratis"
DEFAULT_IGNORE=""

# ---------------------------------------------------------------- options ---

ORGS="${GH_SUBSCRIBE_ORGS:-$DEFAULT_ORGS}"
IGNORE="${GH_SUBSCRIBE_IGNORE:-$DEFAULT_IGNORE}"
JOBS="${GH_SUBSCRIBE_JOBS:-4}"
DRY_RUN=false
DO_WATCH=true
DO_FOLLOW=true
INCLUDE_ARCHIVED=false
INCLUDE_FORKS=false
DEFAULT_IGNORES=true
UNWATCH=false

usage() { sed -n '2,45p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

add_ignore() { if [ -z "$IGNORE" ]; then IGNORE="$1"; else IGNORE="$IGNORE,$1"; fi; }

while [ $# -gt 0 ]; do
    case "$1" in
        --orgs)               ORGS="${2:?--orgs needs a value}"; shift 2 ;;
        --orgs=*)             ORGS="${1#*=}"; shift ;;
        --ignore)             add_ignore "${2:?--ignore needs a value}"; shift 2 ;;
        --ignore=*)           add_ignore "${1#*=}"; shift ;;
        --jobs)               JOBS="${2:?--jobs needs a value}"; shift 2 ;;
        --jobs=*)             JOBS="${1#*=}"; shift ;;
        -n|--dry-run)         DRY_RUN=true; shift ;;
        --no-follow)          DO_FOLLOW=false; shift ;;
        --no-watch)           DO_WATCH=false; shift ;;
        --include-archived)   INCLUDE_ARCHIVED=true; shift ;;
        --include-forks)      INCLUDE_FORKS=true; shift ;;
        --no-default-ignores) DEFAULT_IGNORES=false; shift ;;
        --unwatch)            UNWATCH=true; DO_FOLLOW=false; shift ;;
        -h|--help)            usage 0 ;;
        *)                    printf 'unknown option: %s\n\n' "$1" >&2; usage 1 ;;
    esac
done

# ----------------------------------------------------------------- output ---

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    BOLD=$(printf '\033[1m'); DIM=$(printf '\033[2m'); RED=$(printf '\033[31m')
    GREEN=$(printf '\033[32m'); YELLOW=$(printf '\033[33m'); RESET=$(printf '\033[0m')
else
    BOLD=""; DIM=""; RED=""; GREEN=""; YELLOW=""; RESET=""
fi

info()  { printf '%s\n' "$*"; }
head1() { printf '\n%s%s%s\n' "$BOLD" "$*" "$RESET"; }
ok()    { printf '  %s✓%s %s\n' "$GREEN" "$RESET" "$*"; }
muted() { printf '  %s⊘%s %s\n' "$DIM" "$RESET" "$*"; }
warn()  { printf '  %s!%s %s\n' "$YELLOW" "$RESET" "$*"; }
fail()  { printf '  %s✗%s %s\n' "$RED" "$RESET" "$*"; }
note()  { printf '  %s%s%s\n' "$DIM" "$*" "$RESET"; }
die()   { printf '%serror:%s %s\n' "$RED" "$RESET" "$*" >&2; exit 1; }

TMP=$(mktemp -d "${TMPDIR:-/tmp}/gh-subscribe.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
TAB=$(printf '\t')

lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# Normalize the comma-separated inputs into line-per-entry files once, so the
# rest of the script never has to juggle IFS.
split_list() { printf '%s' "$1" | tr ',' '\n' | tr -d ' ' | grep -v '^$' || true; }

split_list "$ORGS" > "$TMP/orgs"
split_list "$IGNORE" | tr '[:upper:]' '[:lower:]' > "$TMP/ignore-patterns"

# -------------------------------------------------------------- preflight ---

command -v gh >/dev/null 2>&1 || die "gh is not installed — see https://cli.github.com"
gh auth status >/dev/null 2>&1 || die "not logged in — run: gh auth login"

VIEWER=$(gh api user --jq '.login')
SCOPES=$(gh api -i user 2>/dev/null | tr -d '\r' | awk 'tolower($1) == "x-oauth-scopes:" { $1=""; print }' | tr -d ' ')

has_scope() {
    case ",$SCOPES," in *",$1,"*) return 0 ;; *) return 1 ;; esac
}

head1 "GitHub subscriptions for ${VIEWER}"
note "orgs: ${ORGS}"
[ -n "$IGNORE" ] && note "ignore: ${IGNORE}"
$DEFAULT_IGNORES && note "muting archived repos and forks by default"
$DRY_RUN && note "dry run — no changes will be made"

if $DO_WATCH && ! has_scope repo; then
    die "missing 'repo' scope (needed to manage subscriptions). Run:
    gh auth refresh -h github.com -s repo"
fi

if $DO_FOLLOW && ! has_scope user:follow; then
    warn "missing 'user:follow' scope — skipping the follow step."
    note "to enable it, run this once and re-run the script:"
    note "    gh auth refresh -h github.com -s user:follow"
    DO_FOLLOW=false
fi

$DO_FOLLOW && ! has_scope read:org && warn "missing 'read:org' scope — member lists may be incomplete."

# --------------------------------------------------------------- watching ---

WATCHED=0; IGNORED=0; DROPPED=0; CORRECT=0; UNTOUCHED=0; FAILED=0

# Decide the desired state for one repo: watch, ignore, or leave alone.
desired_state() {
    _name=$(lower "${1#*/}"); _full=$(lower "$1"); _archived="$2"; _fork="$3"

    while IFS= read -r _pattern; do
        # shellcheck disable=SC2254  # unquoted: glob matching is the point
        case "$_name" in $_pattern) printf 'ignore'; return ;; esac
        # shellcheck disable=SC2254
        case "$_full" in $_pattern) printf 'ignore'; return ;; esac
    done < "$TMP/ignore-patterns"

    if [ "$_archived" = "true" ]; then
        $INCLUDE_ARCHIVED && { printf 'watch'; return; }
        $DEFAULT_IGNORES  && { printf 'ignore'; return; }
        printf 'leave'; return
    fi

    if [ "$_fork" = "true" ]; then
        $INCLUDE_FORKS   && { printf 'watch'; return; }
        $DEFAULT_IGNORES && { printf 'ignore'; return; }
        printf 'leave'; return
    fi

    printf 'watch'
}

# Is this repo already muted? Costs an API call, so only asked of ignore targets —
# `user/subscriptions` lists only subscribed repos, never ignored ones.
is_ignored() {
    [ "$(gh api "repos/$1/subscription" --jq '.ignored' 2>/dev/null)" = "true" ]
}

is_watched() { grep -qxF "$(lower "$1")" "$TMP/watched-lc"; }

plan_org() {
    org="$1"

    gh repo list "$org" --limit 1000 --json nameWithOwner,isArchived,isFork \
        --jq '.[] | [.nameWithOwner, .isArchived, .isFork] | @tsv' \
        > "$TMP/repos" 2>"$TMP/err" || {
        fail "could not list repos for '$org': $(cat "$TMP/err")"
        return 1
    }

    total=$(wc -l < "$TMP/repos" | tr -d ' ')
    [ "$total" -gt 0 ] || { warn "no repositories found in '$org'"; return 0; }

    : > "$TMP/todo"
    while IFS="$TAB" read -r repo archived fork; do
        [ -n "$repo" ] || continue

        if $UNWATCH; then
            if is_watched "$repo"; then printf 'delete:%s\n' "$repo" >> "$TMP/todo"
            else UNTOUCHED=$((UNTOUCHED + 1)); fi
            continue
        fi

        case "$(desired_state "$repo" "$archived" "$fork")" in
            watch)
                if is_watched "$repo"; then CORRECT=$((CORRECT + 1))
                else printf 'watch:%s\n' "$repo" >> "$TMP/todo"; fi
                ;;
            ignore)
                if is_ignored "$repo"; then CORRECT=$((CORRECT + 1))
                else printf 'ignore:%s\n' "$repo" >> "$TMP/todo"; fi
                ;;
            leave) UNTOUCHED=$((UNTOUCHED + 1)) ;;
        esac
    done < "$TMP/repos"

    todo=$(wc -l < "$TMP/todo" | tr -d ' ')
    info "  ${org}: ${total} repos, ${todo} to change, ${CORRECT} already correct"

    [ "$todo" -gt 0 ] || return 0

    if $DRY_RUN; then
        while IFS=':' read -r action repo; do note "would ${action} ${repo}"; done < "$TMP/todo"
        return 0
    fi

    # shellcheck disable=SC2016  # $0 is expanded by the inner `bash -c`
    xargs -P "$JOBS" -n1 bash -c '
        action=${0%%:*}; repo=${0#*:}
        case $action in
            watch)  set -- -X PUT -F subscribed=true -F ignored=false ;;
            ignore) set -- -X PUT -F subscribed=false -F ignored=true ;;
            delete) set -- -X DELETE ;;
        esac
        if gh api "$@" "repos/$repo/subscription" --silent >/dev/null 2>&1
        then echo "ok $action $repo"; else echo "fail $action $repo"; fi
    ' < "$TMP/todo" > "$TMP/results" || true

    while read -r status action repo; do
        case "$status:$action" in
            ok:watch)  ok "watching $repo";   WATCHED=$((WATCHED + 1)) ;;
            ok:ignore) muted "muted $repo";   IGNORED=$((IGNORED + 1)) ;;
            ok:delete) muted "dropped $repo"; DROPPED=$((DROPPED + 1)) ;;
            fail:*)    fail "$action $repo";  FAILED=$((FAILED + 1)) ;;
        esac
    done < "$TMP/results"
}

if $DO_WATCH; then
    head1 "Repositories"
    gh api user/subscriptions --paginate --jq '.[].full_name' 2>/dev/null \
        | tr '[:upper:]' '[:lower:]' | sort > "$TMP/watched-lc" || : > "$TMP/watched-lc"
    note "currently watching $(wc -l < "$TMP/watched-lc" | tr -d ' ') repos in total"

    while IFS= read -r org; do plan_org "$org"; done < "$TMP/orgs"
fi

# -------------------------------------------------------------- following ---

FOLLOWED=0; FOLLOW_CORRECT=0; FOLLOW_FAILED=0

follow_org() {
    org="$1"

    gh api "orgs/$org/members" --paginate --jq '.[].login' > "$TMP/members" 2>"$TMP/err" || {
        fail "could not list members of '$org': $(cat "$TMP/err")"
        return 1
    }

    total=$(wc -l < "$TMP/members" | tr -d ' ')
    [ "$total" -gt 0 ] || { warn "no members visible in '$org'"; return 0; }

    : > "$TMP/todo"
    while IFS= read -r user; do
        [ -n "$user" ] || continue
        if [ "$(lower "$user")" = "$(lower "$VIEWER")" ] \
           || grep -qxF "$(lower "$user")" "$TMP/following-lc"; then
            FOLLOW_CORRECT=$((FOLLOW_CORRECT + 1))
        else
            printf '%s\n' "$user" >> "$TMP/todo"
        fi
    done < "$TMP/members"

    todo=$(wc -l < "$TMP/todo" | tr -d ' ')
    info "  ${org}: ${total} members, ${todo} to follow"

    [ "$todo" -gt 0 ] || return 0

    if $DRY_RUN; then
        while IFS= read -r user; do note "would follow ${user}"; done < "$TMP/todo"
        return 0
    fi

    # shellcheck disable=SC2016  # $0 is expanded by the inner `bash -c`
    xargs -P "$JOBS" -n1 bash -c \
        'if gh api -X PUT "user/following/$0" --silent >/dev/null 2>&1; then echo "ok $0"; else echo "fail $0"; fi' \
        < "$TMP/todo" > "$TMP/results" || true

    while IFS=' ' read -r status user; do
        case "$status" in
            ok)   ok "$user"; FOLLOWED=$((FOLLOWED + 1)) ;;
            fail) fail "$user"; FOLLOW_FAILED=$((FOLLOW_FAILED + 1)) ;;
        esac
    done < "$TMP/results"
}

if $DO_FOLLOW; then
    head1 "People"
    gh api user/following --paginate --jq '.[].login' 2>/dev/null \
        | tr '[:upper:]' '[:lower:]' | sort > "$TMP/following-lc" || : > "$TMP/following-lc"
    note "currently following $(wc -l < "$TMP/following-lc" | tr -d ' ') users in total"

    while IFS= read -r org; do follow_org "$org"; done < "$TMP/orgs"
fi

# ---------------------------------------------------------------- summary ---

head1 "Summary"
$DO_WATCH  && info "  repos    ${WATCHED} watched, ${IGNORED} muted, ${DROPPED} dropped, ${CORRECT} already correct, ${UNTOUCHED} left alone, ${FAILED} failed"
$DO_FOLLOW && info "  people   ${FOLLOWED} followed, ${FOLLOW_CORRECT} already correct, ${FOLLOW_FAILED} failed"

if $DRY_RUN; then
    printf '\n%sDry run — nothing was changed. Re-run without --dry-run to apply.%s\n' "$DIM" "$RESET"
else
    printf '\n%sOne thing this script cannot do:%s GitHub has no API for email delivery\n' "$BOLD" "$RESET"
    printf 'preferences. Make sure %sEmail%s is ticked for "Watching" and "Participating"\n' "$BOLD" "$RESET"
    printf 'at %shttps://github.com/settings/notifications%s — otherwise these subscriptions\n' "$DIM" "$RESET"
    printf 'only show up in the web inbox.\n'
fi

[ "$FAILED" -eq 0 ] && [ "$FOLLOW_FAILED" -eq 0 ]
