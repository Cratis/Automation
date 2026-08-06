# Notifications

How to make sure GitHub tells you what is happening across the Cratis org — the
repositories that matter watched, the noise actively muted, delivered by email.

GitHub only notifies you about repositories you *watch*. Repositories you have
merely cloned, contributed to once, or have write access to generate nothing.
New repositories appear in the org regularly, so the set drifts out of date on
its own. `gh-subscribe.sh` reconciles it in one command.

## Setup checklist

Do these once. Steps 1–3 are scripted; steps 4–6 are web UI only, because
GitHub exposes no API for notification delivery preferences. Skipping step 4 is
the usual reason someone watches everything and still receives no email.

You do not need to be an org member to run this — non-members get the org's
public repositories and public member list.

- [ ] **1. Install and authenticate the GitHub CLI** — `gh auth login`.
      Requires [gh](https://cli.github.com) 2.0+.
- [ ] **2. Run the script** — `cd Source/GitHub && ./gh-subscribe.sh`.
      Preview first with `--dry-run` if you want to see the plan.
- [ ] **3. Say yes when it offers to add the `user:follow` scope** — the script
      detects the missing scope and offers to run `gh auth refresh` for you.
      Answer `n` (or run non-interactively) and it manages repositories only,
      which is a perfectly good outcome if you would rather not follow people.
      To do it by hand: `gh auth refresh -h github.com -s user:follow`.
- [ ] **4. Turn on email delivery** — at
      [github.com/settings/notifications](https://github.com/settings/notifications),
      under **Subscriptions**, tick **Email** for **Watching** *and* for
      **Participating, @mentions and custom**.
- [ ] **5. Check the address** — confirm **Default notification email** is one
      you actually read, and that it is verified under
      [github.com/settings/emails](https://github.com/settings/emails).
      Unverified addresses receive nothing.
- [ ] **6. Enable automatic watching** — still on the notifications page, tick
      **Automatically watch repositories**. New repositories you gain access to
      are then watched on their own, so the set drifts less between runs.

Optional:

- [ ] **Mute what you don't care about** — `--ignore 'Samples,*.github.io'`, or
      export `GH_SUBSCRIBE_IGNORE` to make it stick. See
      [Muting more than the defaults](#muting-more-than-the-defaults).
- [ ] **Route Cratis mail separately** — **Custom routing** on the notifications
      page can send org notifications to a different verified address.
- [ ] **Re-run after new repositories appear** — the script is idempotent, so
      `./gh-subscribe.sh` is safe to run any time.

## Watching, ignoring, and doing nothing

The script drives every repository in the org to one of two **explicit** states:

| State      | API                              | Effect                                              |
| ---------- | -------------------------------- | --------------------------------------------------- |
| **watch**  | `subscribed=true, ignored=false` | Notified about all activity                          |
| **ignore** | `subscribed=false, ignored=true` | Muted — nothing, not even `@mentions`                |

Ignoring is deliberately stronger than simply not watching. An unwatched
repository still notifies you when someone mentions you or you comment on a
thread; an ignored one never does. That is the point — a repository you have
decided is noise should stay quiet even when someone drags you into a thread.

Archived repositories and forks are ignored by default. Everything else in the
org is watched.

## Prerequisites

- [GitHub CLI](https://cli.github.com) 2.0+, authenticated with `gh auth login`.
- Token scopes:
  - `repo` — required, to read and write repository subscriptions.
  - `read:org` — required, to list org members.
  - `user:follow` — optional, only to follow people. Add it with
    `gh auth refresh -h github.com -s user:follow`.

The script checks these up front and tells you the exact command to run if
something is missing. Without `user:follow` it degrades to managing
repositories only rather than failing.

## Usage

```bash
cd Source/GitHub
./gh-subscribe.sh
```

That watches every repository in the `Cratis` org, mutes archived repos and
forks, and follows every org member. It is idempotent — it reads your current
state first and only writes what is actually wrong, so re-running it after new
repositories appear costs a few API calls and changes nothing else.

Preview before committing to anything:

```bash
./gh-subscribe.sh --dry-run
```

## Muting more than the defaults

Pass shell globs to `--ignore`. They are matched case-insensitively against
both the repository name and its full name, so `Samples` and `Cratis/Samples`
are equivalent:

```bash
./gh-subscribe.sh --ignore 'Samples,Workshops,*.github.io'
```

Make it permanent for your machine by exporting the same list, which keeps your
personal taste out of the shared script:

```bash
export GH_SUBSCRIBE_IGNORE='Samples,Workshops,*.github.io'
```

## Options

| Option                 | Effect                                                      |
| ---------------------- | ----------------------------------------------------------- |
| `--dry-run`, `-n`      | Print what would change, write nothing                      |
| `--orgs A,B`           | Target other orgs (default `Cratis`)                        |
| `--ignore PAT,...`     | Mute repositories matching these globs                      |
| `--no-follow`          | Manage repositories, skip following people                  |
| `--no-watch`           | Follow people, skip repositories                            |
| `--include-archived`   | Watch archived repositories instead of muting them          |
| `--include-forks`      | Watch forks instead of muting them                          |
| `--no-default-ignores` | Leave archived repos and forks alone rather than muting     |
| `--unwatch`            | Reverse: drop every subscription to the org's repositories   |
| `--jobs N`             | Parallel API calls (default 4)                              |

Environment overrides: `GH_SUBSCRIBE_ORGS`, `GH_SUBSCRIBE_IGNORE`,
`GH_SUBSCRIBE_JOBS`.

The script exits non-zero if any call failed, so it is safe to chain in a
larger setup script.

## Why email delivery is manual

GitHub's REST and GraphQL APIs cover *subscriptions* — which repositories
generate notifications — but expose nothing for *delivery*: the Email
checkboxes, the default notification address, and per-organization routing are
all web UI only. No script can set them, which is why steps 4–6 of the
checklist are done by hand and why the script prints a reminder on every run.

The practical consequence: subscriptions and delivery fail independently. If
mail stops arriving, check both — the repository's subscription state (see
[Checking the result](#checking-the-result)) and the delivery settings.

## What the script cannot do

- **Set email preferences** — see above; web UI only.
- **Set partial watch modes.** The REST API supports only "all activity" and
  "ignore". The finer-grained choices (releases only, issues only, discussions
  only) exist in the web UI and have no API equivalent, so pick those by hand
  on any repository where all-activity is too noisy but silence is too far.

## Clearing done items from the inbox

Watching gets the right notifications *created*; it does nothing about
notifications that are still sitting in your inbox after the thing they were
about is resolved. A PR notification stays there after the PR is merged, and
an issue notification stays there after the issue is closed — GitHub never
cleans these up on its own. `gh-inbox-done.sh` marks any such thread "done" —
the same action as the checkmark in the web inbox — so what is left in your
inbox is only things that still need a look.

```bash
cd Source/GitHub
./gh-inbox-done.sh
```

That sweeps every notification (read and unread), and for each one pointing
at an issue or pull request, fetches its current state and marks the thread
done when the issue is closed or the PR is merged or closed. Everything else
— releases, discussions, commits, Copilot agent-session threads, and
anything still open — is left alone.

Preview first:

```bash
./gh-inbox-done.sh --dry-run
```

Options:

| Option            | Effect                                                            |
| ----------------- | ----------------------------------------------------------------- |
| `--dry-run`, `-n` | Print what would be marked done, write nothing                    |
| `--unread-only`   | Only scan currently-unread notifications (faster, incremental)    |
| `--merged-only`   | Leave closed-but-unmerged pull requests alone                     |
| `--verbose`, `-v` | Also print what was left alone, and why                           |
| `--jobs N`        | Parallel API calls (default 4; override via `GH_INBOX_DONE_JOBS`) |

Marking a thread done is reversible — it only leaves the default inbox view.
The thread is still there under the `is:done` filter on
[github.com/notifications](https://github.com/notifications) and can be
marked unread again from there.

## Checking the result

```bash
# How many Cratis repos am I watching?
gh api user/subscriptions --paginate --jq '.[].full_name' | grep -c '^Cratis/'

# State for one repo. 404 means neither watched nor ignored — GitHub only
# stores a subscription record once you have explicitly chosen a state.
gh api repos/Cratis/Chronicle/subscription

# Unread notifications, without opening a browser.
gh api notifications --jq '.[] | "\(.repository.full_name): \(.subject.title)"'
```

Note that `user/subscriptions` lists only *watched* repositories — ignored ones
are absent from it. That is why the script checks ignore candidates one at a
time rather than trusting the bulk list.
