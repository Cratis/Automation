# GitHub Copilot Coding Agent

Prepare a repository for a bounded issue assigned to **@copilot**, then review the resulting work through its PR and checks. Start with access and repository policy, install the hosted setup workflow, and give the agent the commands and constraints it needs for that task. A PR or a green check is a handoff to review, not approval to merge.

This guide covers the GitHub-hosted setup path. The local runner image is useful for comparing tools and commands, but it does not supply that hosted environment. For building or registering the image itself, use [local setup](local-setup.md).

## 1. Enable Copilot on the org/repo

An organization administrator chooses which repositories may use the agent. Before enabling it or assigning work, have that administrator confirm access for the people assigning tasks, applicable usage costs and any required approvals. Keep credential values out of issues and instruction files.

1. In **Org settings -> Copilot -> Policies**, enable
   *Copilot coding agent* for the org (or the specific repos you want).
2. In **Repo settings -> Copilot -> Coding agent**, confirm it's enabled.
3. Confirm that the intended maintainer can assign work in that repository. If the controls are unavailable, resolve account and organization policy with the administrator before continuing.

## 2. Provision the agent's environment

For this hosted path, copy the setup workflow into the repository where the agent will work; building the local Docker image does not install it. Review the workflow's actions and shell commands before enabling a run: they execute setup work in GitHub Actions. The template requests only `contents: read` for its job, not runner-registration or package-publishing access.

Use [GitHub's environment setup guide](https://docs.github.com/en/copilot/how-tos/use-copilot-agents/coding-agent/customize-the-agent-environment) for the service-side setup, then install the repository template:

1. Copy `Source/GitHub/copilot-setup-steps.yml` to
   `.github/workflows/copilot-setup-steps.yml`.
2. Keep the job named `copilot-setup-steps`; this is the name the template uses for the hosted bootstrap.
3. Check the copied workflow in Actions before assigning an issue. The template supports manual dispatch and runs when that installed workflow changes. Inspect the setup steps and their logs; a successful setup run is the first result to establish, not evidence that the repository's build or tests passed.

The template requests these tools:

- .NET 9 and 10 SDKs
- Node 24 + `pnpm@latest` via Corepack
- Python 3.12

It also contains conditional `dotnet restore` and `pnpm install --frozen-lockfile` steps. Those commands prepare repository dependencies; installing the SDKs alone does not populate every project's NuGet or pnpm caches. Read the copied workflow when changing what your repository needs.

Choose the tools for the commands your repository actually runs. A workflow targeting `runs-on: self-hosted` and a hosted Copilot task need compatible prerequisites, but one environment is not proof of the other. The Dockerfile and hosted setup select versions independently, including a fixed pnpm selection in the image and `pnpm@latest` in the setup workflow. If setup fails, use [the Copilot toolchain checks](troubleshooting.md#copilot-prs-come-up-with-the-wrong-toolchain) to check the installed filename, job name and failing run before assigning work.

## 3. Give the agent project context

Put the repository's build and test commands, generated-file boundaries and task constraints where a contributor can find them. In this repository, `AGENTS.md` points to `.cratis/ai/rules/project.md`, which links the project concerns. Keep `CONTRIBUTING.md` accurate where the target repository has one. These files explain how to work; they do not authorize a wider task, credential disclosure or publication.

The stub below illustrates basic commands for a C# project. Replace its assumptions with the target repository's actual commands and conventions rather than treating it as a complete CI definition:

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

After checking setup, choose one issue with a concrete outcome, relevant files and a check the maintainer will use to judge the result. State what is outside the task, especially publishing, deployments and access to live systems.

Assign the issue to **Copilot** in the Assignees sidebar. If that option is unavailable, return to the access and policy checks above; do not treat a comment as confirmation that the issue has been assigned.

Follow the work in the session and PR that GitHub makes available. Inspect the setup result first, then the proposed diff and the checks for the target repository. A branch such as `copilot/<issue-number>-<slug>` identifies the attempt; it does not tell you whether the task succeeded.

When a PR appears, compare its changes with the issue and inspect the actual build and test results. If work stops at a failed command, use that command and its log to decide whether to repair setup or revise the task. Do not infer success from a notification or *Ready for review* status.

## 5. Review workflow

- Review the diff against the issue, including generated-file and authorization boundaries; request concrete changes with inline comments.
- When using `@copilot` to request another iteration on a PR, inspect the resulting activity and checks rather than assuming the mention completed the change.
- Complete the repository's required review and checks before merging. Green CI is evidence to inspect, not permission to bypass review.

## 6. Limits & gotchas

- Keep work in a PR and follow the repository's protected-branch and required-review policy; do not treat agent access as approval to bypass it.
- For a dependency or network failure, inspect the failed setup command and the repository's approved feed and network configuration. The setup file alone does not define the hosted service's egress policy.
- Have the administrator check **Repo settings -> Environments -> copilot** and the current service setup before supplying a task-required credential. Do not assume regular Actions secrets are available, and never copy their values into an issue, instruction file or PR.
- Keep `copilot-setup-steps.yml` working before delegating another task. Inspect the failed step before deciding whether to retry the task or repair its setup.

## 7. Checking the toolchain locally

If a Copilot PR fails, identify the failed hosted setup or repository command first. You can then compare that command with a local run in the image. Follow [local setup](local-setup.md) for Docker, platform selection and the [socket-mount controls](local-setup.md#docker-in-docker-vs-socket-mount) before starting the container: the helper mounts an available host Docker socket by default even in shell mode.

Start the block below from the Automation checkout root. `RUNNER_MODE=shell` opens a local shell without registering a runner; it does not start the hosted agent. Inside that shell, replace `<repo>` with the target repository name before using the clone command:

```bash
cd Source/GitHub
RUNNER_MODE=shell ./run-local.sh
# inside:
git clone https://github.com/cratis/<repo>.git && cd <repo>
dotnet restore && dotnet build && dotnet test
```

A local failure gives you a command and error to compare with the hosted logs. If the local commands pass but the hosted task fails, compare tool versions with `dotnet --info`, `node --version` and `pnpm --version`, then return to the failed hosted step. The Docker image and setup workflow choose their tools separately, so a local pass does not establish a hosted pass. Use [troubleshooting](troubleshooting.md#copilot-prs-come-up-with-the-wrong-toolchain) to continue with the setup filename, job name and run checks.
