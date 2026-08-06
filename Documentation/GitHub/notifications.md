# Notifications

How to make sure GitHub tells you what is happening across the Cratis org — the
repositories that matter watched, the noise actively muted, delivered by email.

GitHub only notifies you about repositories you *watch*. Repositories you have
merely cloned, contributed to once, or have write access to generate nothing.
New repositories appear in the org regularly, so the set drifts out of date on
its own. `gh-subscribe.sh` reconciles it in one command.

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

## Turn on email delivery

**This step cannot be scripted.** GitHub exposes no API for notification
delivery preferences, so watching every repository still only fills the web
inbox until you opt into email once:

1. Go to [github.com/settings/notifications](https://github.com/settings/notifications).
2. Under **Subscriptions**, tick **Email** for both **Watching** and
   **Participating, @mentions and custom**.
3. Confirm the address under **Default notification email** is one you read,
   and that it is verified.

Organizations can route to a different address than your default. If you want
Cratis notifications separate from everything else, set a per-org address on
the same page under **Custom routing**.

## What the script cannot do

- **Set email preferences** — see above; web UI only.
- **Set partial watch modes.** The REST API supports only "all activity" and
  "ignore". The finer-grained choices (releases only, issues only, discussions
  only) exist in the web UI and have no API equivalent, so pick those by hand
  on any repository where all-activity is too noisy but silence is too far.

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
