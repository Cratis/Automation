#!/usr/bin/env bash
# Run the custom runner image locally.
#
# Examples:
#   # Interactive shell for poking around:
#   RUNNER_MODE=shell ./run-local.sh
#
#   # Register as a self-hosted runner for this repo:
#   GITHUB_URL=https://github.com/cratis/automation \
#   GITHUB_PAT=ghp_xxx \
#   ./run-local.sh

set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-cratis/gh-runner}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
RUNNER_MODE="${RUNNER_MODE:-actions}"

args=(
    --rm
    -e RUNNER_MODE="${RUNNER_MODE}"
)

[[ -n "${GITHUB_URL:-}"    ]] && args+=(-e GITHUB_URL="${GITHUB_URL}")
[[ -n "${GITHUB_PAT:-}"    ]] && args+=(-e GITHUB_PAT="${GITHUB_PAT}")
[[ -n "${RUNNER_TOKEN:-}"  ]] && args+=(-e RUNNER_TOKEN="${RUNNER_TOKEN}")
[[ -n "${RUNNER_NAME:-}"   ]] && args+=(-e RUNNER_NAME="${RUNNER_NAME}")
[[ -n "${RUNNER_LABELS:-}" ]] && args+=(-e RUNNER_LABELS="${RUNNER_LABELS}")

if [[ "${RUNNER_MODE}" == "shell" ]]; then
    args+=(-it)
fi

if [[ "${MOUNT_DOCKER_SOCK:-1}" == "1" && -S /var/run/docker.sock ]]; then
    args+=(-v /var/run/docker.sock:/var/run/docker.sock)
fi

exec docker run "${args[@]}" "${IMAGE_NAME}:${IMAGE_TAG}"
