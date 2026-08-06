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
| `notifications.md`          | Get notified about the right repos, by email                |

## Quick start

```bash
# 1. Build the image locally.
cd Source/GitHub
./build.sh

# 2. Put credentials in ~/.cratis-gh-runner.env (chmod 600 it) - never
#    export GITHUB_PAT and pass it as -e, that lands the secret in the
#    `docker run` command line where any local process can read it via `ps`.
#      GITHUB_URL=https://github.com/cratis/automation
#      GITHUB_PAT=ghp_xxx   (needs `repo` + `workflow` scope)

# 3. Register a runner against this repo.
./run-local.sh
```

See `local-setup.md` for full details.
