# Local Setup

Build the image on your workstation, then choose whether to inspect its tools or register it to accept a GitHub Actions job. You need access to the target repository only for registration; shell mode lets you inspect the image without registering a runner.

Use a host you trust with the jobs it will accept. Do not send public-repository pull-request jobs to a self-hosted runner. The helper mounts an available host Docker socket by default, giving jobs control of the host Docker daemon; read [the socket-mount options](#docker-in-docker-vs-socket-mount) before starting it.

## Prerequisites

- Docker 24+ with Buildx (`docker buildx version` must succeed).
- A GitHub Personal Access Token (classic) with `repo` and `workflow` scopes,
  or a fine-grained token with `Actions: read & write` and
  `Administration: read & write` on the target repo.
- ~4 GB free disk space for the image.

## Build

From the repository root, build and load the image into your local Docker image store:

```bash
cd Source/GitHub
./build.sh
```

The helper reports the image name, tag and platform when the build succeeds. With the defaults below, expect `Built cratis/gh-runner:latest for linux/amd64`. The run helper uses that locally loaded image. Choose the platform before building; for an Apple Silicon native image, use the `linux/arm64` override rather than the default emulated architecture.

Useful environment overrides:

| Variable     | Default              | Notes                             |
| ------------ | -------------------- | --------------------------------- |
| `IMAGE_NAME` | `cratis/gh-runner`   | Image repository name             |
| `IMAGE_TAG`  | `latest`             | Tag                               |
| `PLATFORM`   | `linux/amd64`        | e.g. `linux/arm64` on Apple Silicon |

You can now skip to [Run](#run) for local use. Publishing a multi-arch image is a separate task: the following command pushes to GHCR and requires permission to push the target image. Return to the repository root first, because this command uses `Source/GitHub` as its build context. For the administrator publishing workflow, use [GitHub configuration](github-configuration.md).

Multi-arch build for publishing:

```bash
docker buildx build \
    --platform linux/amd64,linux/arm64 \
    --tag ghcr.io/cratis/gh-runner:dev \
    --push \
    Source/GitHub
```

## Run

Run the commands below from `Source/GitHub`, using the image you built. `RUNNER_MODE` chooses between accepting a GitHub Actions job, opening a shell and leaving a local container idle. The latter two modes do not register an Actions runner.

### 1. As a self-hosted runner (default)

Keep secrets (`GITHUB_PAT`, `RUNNER_TOKEN`) in an env file; never put their values in `docker run` arguments, where local processes can inspect them through `ps`. Create `~/.cratis-gh-runner.env` and restrict it with `chmod 600` before supplying credentials. The example registers against one repository; its PAT needs the permissions listed above. For an organization, supply an org-level registration token as described in [GitHub configuration](github-configuration.md#option-b---organization-runners-recommended).

```bash
GITHUB_URL=https://github.com/cratis/automation
GITHUB_PAT=ghp_xxxxxxxxxxxxxxxx
```

With the file in place, start the container:

```bash
./run-local.sh
```

The entrypoint exchanges a repository PAT for a short-lived registration token and configures the runner in `--ephemeral` mode to accept one job. Check the target repository's Actions runner settings for its registration and status before expecting a workflow to select it. If it does not appear online, start with the container logs in [troubleshooting](troubleshooting.md#the-runner-never-comes-online).

The entrypoint attempts to remove its registration on shutdown; this is not host isolation. For several runners, run `docker compose up --scale runner=N` from `Source/GitHub`. Compose restarts the service after it exits and reuses its container filesystem, so do not treat each registration as a fresh host.

If you already have a registration token, put it in the file instead of the PAT. To request a repository token with the command below, your GitHub CLI session must already have access to administer runners for that repository. Generate it shortly before starting the runner, then put the result in the same protected file:

```bash
RUNNER_TOKEN=$(gh api -X POST \
    repos/cratis/automation/actions/runners/registration-token --jq .token)
```

```bash
# ~/.cratis-gh-runner.env
GITHUB_URL=https://github.com/cratis/automation
RUNNER_TOKEN=<paste the token here>
```

Override the file location with `RUNNER_ENV_FILE`. The helper also folds in exported `GITHUB_URL`, `GITHUB_PAT`, `RUNNER_TOKEN`, `RUNNER_NAME` and `RUNNER_LABELS`, which take precedence over the file. It writes a private temporary env file and passes that file to Docker, keeping these values out of its own `docker run` argv. This does not make exported credentials private from the surrounding host environment; use the protected file for secrets.

### 2. Interactive shell (for debugging the image)

Use this mode to inspect the installed tools without exchanging a token or accepting a job:

```bash
RUNNER_MODE=shell ./run-local.sh
# inside the container:
dotnet --info
node --version
pnpm --version
```

### 3. Copilot-style environment

This mode leaves a local container idle for `docker exec`; it does not start GitHub's hosted Copilot coding agent. To configure that agent, follow [the Copilot guide](copilot-agent.md).

```bash
RUNNER_MODE=copilot ./run-local.sh
# container idles so you can `docker exec` into it the way Copilot does.
```

## Tear-down

The runner is configured for one job, and its shutdown handler attempts to remove its registration. A crash can interrupt cleanup. If a runner is stuck in **Offline** state in the repository settings, identify that runner before removing it from the UI or with the existing command below:

```bash
gh api -X DELETE repos/cratis/automation/actions/runners/<id>
```

## Docker-in-Docker vs socket mount

`run-local.sh` mounts `/var/run/docker.sock` by default when that socket exists; `docker-compose.yml` declares the mount unconditionally. This lets job steps use the host Docker daemon instead of a nested daemon, and gives those jobs root-level control of the host.

Set `MOUNT_DOCKER_SOCK=0` to disable the helper's mount before starting it. Compose does not read that switch: changing its mount requires separate configuration. Jobs that rely on the socket then need another Docker/build service; the runner does not configure one for you.
