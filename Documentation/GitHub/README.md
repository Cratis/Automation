# GitHub Automation

Cratis Automation provides a Docker image and helper scripts for running GitHub Actions jobs with the Cratis toolchain already installed. Start with [local setup](local-setup.md) to build the image and either inspect it in a shell or register it for a trusted repository.

If you administer runners for several repositories, continue with [GitHub configuration](github-configuration.md) to publish the image and choose a runner host. The [Copilot coding agent guide](copilot-agent.md) is a separate route: GitHub hosts that agent and uses a setup workflow to prepare its environment.

## Why a custom image?

On a hosted `ubuntu-latest` runner, a workflow may install its required SDKs with `actions/setup-dotnet`, `actions/setup-node` and similar steps. A self-hosted runner using this image starts with those tools installed, so workflows can avoid reinstalling the tools the image already supplies. Matrix jobs can reuse that preparation too.

Project dependencies still need restoring: building the image does not fill a repository's NuGet or pnpm caches. Copilot's hosted setup workflow and the Dockerfile select their tools independently, so shared build commands do not establish identical environments. Check the tools your repository requires before removing its setup steps.

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

Before starting the runner, follow [local setup](local-setup.md) for prerequisites and credential-file handling. Use a host you trust with its jobs, and do not run public-repository pull-request jobs on it. The helper mounts an available host Docker socket by default, giving jobs control of the host Docker daemon; review [the socket-mount options](local-setup.md#docker-in-docker-vs-socket-mount) before running the commands below. Registration lets GitHub send a job to this machine; it is not just a local image check. Use the shell mode in local setup if you only want to inspect the tools. If registration or job selection fails, use [troubleshooting](troubleshooting.md) to check logs, token access and runner labels.

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
