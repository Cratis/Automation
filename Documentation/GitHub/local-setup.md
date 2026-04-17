# Local Setup

How to build and run the custom GitHub Actions runner image on your workstation.

## Prerequisites

- Docker 24+ with Buildx (`docker buildx version` must succeed).
- A GitHub Personal Access Token (classic) with `repo` and `workflow` scopes,
  or a fine-grained token with `Actions: read & write` and
  `Administration: read & write` on the target repo.
- ~4 GB free disk space for the image.

## Build

```bash
cd Source/GitHub
./build.sh
```

Useful environment overrides:

| Variable     | Default              | Notes                             |
| ------------ | -------------------- | --------------------------------- |
| `IMAGE_NAME` | `cratis/gh-runner`   | Image repository name             |
| `IMAGE_TAG`  | `latest`             | Tag                               |
| `PLATFORM`   | `linux/amd64`        | e.g. `linux/arm64` on Apple Silicon |

Multi-arch build for publishing:

```bash
docker buildx build \
    --platform linux/amd64,linux/arm64 \
    --tag ghcr.io/cratis/gh-runner:dev \
    --push \
    Source/GitHub
```

## Run

Three modes are supported via `RUNNER_MODE`.

### 1. As a self-hosted runner (default)

```bash
export GITHUB_URL=https://github.com/cratis/automation
export GITHUB_PAT=ghp_xxxxxxxxxxxxxxxx
./run-local.sh
```

The entrypoint exchanges the PAT for a short-lived registration token, starts
the runner in `--ephemeral` mode (so it exits after one job), and cleans itself
up on shutdown. Start with `docker-compose up --scale runner=N` for multiple
runners.

You can also skip the PAT exchange and pass a registration token directly:

```bash
RUNNER_TOKEN=$(gh api -X POST \
    repos/cratis/automation/actions/runners/registration-token --jq .token)
GITHUB_URL=https://github.com/cratis/automation RUNNER_TOKEN=$RUNNER_TOKEN \
    ./run-local.sh
```

### 2. Interactive shell (for debugging the image)

```bash
RUNNER_MODE=shell ./run-local.sh
# inside the container:
dotnet --info
node --version
pnpm --version
```

### 3. Copilot-style environment

```bash
RUNNER_MODE=copilot ./run-local.sh
# container idles so you can `docker exec` into it the way Copilot does.
```

## Tear-down

Ephemeral runners remove their own registration. If something crashed and a
runner is stuck in **Offline** state in the repo settings, remove it from the
UI or via:

```bash
gh api -X DELETE repos/cratis/automation/actions/runners/<id>
```

## Docker-in-Docker vs socket mount

`run-local.sh` and `docker-compose.yml` mount the host Docker socket by
default so workflow steps that build container images work without nesting
Docker. Set `MOUNT_DOCKER_SOCK=0` to disable it.
