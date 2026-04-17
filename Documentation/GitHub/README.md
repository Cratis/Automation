# GitHub Automation

This folder documents how we optimize GitHub Actions workflows with a custom
runner image and how we wire up the GitHub Copilot coding agent so it can pick
up assigned issues and work on them inside the same environment.

## Why a custom image?

Hosted `ubuntu-latest` runners ship with a lot of tooling, but they're slow for
Cratis-shaped workloads:

- Every job re-runs `actions/setup-dotnet`, `actions/setup-node`, etc.
- Cold NuGet and pnpm caches add minutes per job.
- Matrix jobs multiply that cost.

Baking the toolchain into an image that we also use as a self-hosted runner
removes that overhead. The same image doubles as the environment for
Copilot-assigned issues, so what the agent runs is what CI runs.

## Documents

| File                        | Read when you want to...                                    |
| --------------------------- | ----------------------------------------------------------- |
| `local-setup.md`            | Build and run the image on your workstation                 |
| `github-configuration.md`   | Register runners and publish the image in GitHub            |
| `copilot-agent.md`          | Enable Copilot coding agent and assign it issues            |
| `workflow-optimization.md`  | Use the image in workflows and keep jobs fast               |
| `troubleshooting.md`        | Diagnose common problems                                    |

## Quick start

```bash
# 1. Build the image locally.
cd Source/GitHub
./build.sh

# 2. Register a runner against this repo (PAT needs `repo` + `workflow` scope).
export GITHUB_URL=https://github.com/cratis/automation
export GITHUB_PAT=ghp_xxx
./run-local.sh
```

See `local-setup.md` for full details.
