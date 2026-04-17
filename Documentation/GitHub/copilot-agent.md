# GitHub Copilot Coding Agent

The coding agent picks up issues assigned to **@copilot**, opens a PR, iterates
until CI is green (or it runs out of steps), and requests your review. Pairing
it with our pre-provisioned environment means it doesn't waste time
re-installing our toolchain.

## 1. Enable Copilot on the org/repo

1. In **Org settings -> Copilot -> Policies**, enable
   *Copilot coding agent* for the org (or the specific repos you want).
2. In **Repo settings -> Copilot -> Coding agent**, confirm it's enabled.
3. Confirm your seat assignment covers the people who will be assigning
   issues - the agent runs under the assigner's identity.

## 2. Provision the agent's environment

The agent always runs inside GitHub-hosted infrastructure, so you can't hand
it our self-hosted image directly. You bootstrap its environment with a
specially-named workflow instead:

1. Copy `Source/GitHub/copilot-setup-steps.yml` to
   `.github/workflows/copilot-setup-steps.yml`.
2. The job **must** be named `copilot-setup-steps` - that's how Copilot finds
   it.
3. Only `actions/checkout` plus setup steps are required. Keep it fast
   (< 2 min) - the agent runs it at the start of every session.

Our template installs:

- .NET 9 and 10 SDKs
- Node 24 + pnpm via Corepack
- Python 3.12
- Restores NuGet and pnpm caches if lockfiles are present

Adjust as needed per repo, but keep it a **superset of what `runs-on:
self-hosted` provides** so the agent hits the same commands CI does.

## 3. Give the agent project context

Two files dramatically improve outcomes:

- `AGENTS.md` (or `.github/copilot-instructions.md`) - house rules: build
  commands, test commands, code style, do/don't lists.
- `CONTRIBUTING.md` - keep it accurate; Copilot reads it.

Example stub for a Cratis project:

```markdown
# Agent Guide

## Build
dotnet build

## Test
dotnet test

## Conventions
- Target .NET 10.
- Namespaces follow the folder structure.
- Don't edit generated files under `**/Generated/**`.
```

## 4. Assign an issue

Either:

- Open an issue and assign it to **Copilot** in the Assignees sidebar, or
- Comment `@copilot please investigate` on an existing issue.

The agent:

1. Spins up a Codespace-like container.
2. Runs `copilot-setup-steps` to hydrate the toolchain.
3. Reads the issue, relevant files, and `AGENTS.md`.
4. Creates a branch like `copilot/<issue-number>-<slug>`, commits, opens a
   draft PR, and runs CI.
5. Iterates on failing checks, then flips the PR to *Ready for review* and
   pings you.

## 5. Review workflow

- Treat the PR like any other - request changes with inline comments.
- Comments starting with `@copilot` in a review spawn another iteration.
- When CI is green and review passes, merge normally.

## 6. Limits & gotchas

- The agent cannot push to protected branches directly - it always goes through
  a PR.
- It has no internet egress to arbitrary hosts; dependency fetching goes
  through the package managers you use in `copilot-setup-steps`.
- Secrets available to the agent are configured separately in
  **Repo settings -> Environments -> copilot** (a dedicated environment GitHub
  creates automatically). Put things like internal feed tokens there; don't
  rely on regular Actions secrets being visible.
- Keep `copilot-setup-steps.yml` green. If it fails, the agent starts from a
  broken environment and its PR will be useless.

## 7. Running the same environment locally

If a Copilot PR is flaky, reproduce it against our image:

```bash
cd Source/GitHub
RUNNER_MODE=shell ./run-local.sh
# inside:
git clone https://github.com/cratis/<repo>.git && cd <repo>
dotnet restore && dotnet build && dotnet test
```

Identical tooling means "works in the agent, fails for me" bugs stay rare.
