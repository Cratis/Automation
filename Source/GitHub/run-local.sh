#!/usr/bin/env bash
# Run the custom runner image locally.
#
# Secrets (GITHUB_PAT, RUNNER_TOKEN) are never passed as `-e` flags - those
# land verbatim in the `docker run` command line, which any local process can
# read via `ps`. Instead they're read from an env file and handed to Docker
# via `--env-file`, so the secret only ever touches a file descriptor.
#
# Put your settings in ~/.cratis-gh-runner.env (chmod 600 it):
#
#   GITHUB_URL=https://github.com/cratis/automation
#   GITHUB_PAT=ghp_xxx
#
# Then just run:
#
#   ./run-local.sh
#
# Override the file location with RUNNER_ENV_FILE. Anything already exported
# in your shell (GITHUB_URL, GITHUB_PAT, RUNNER_TOKEN, RUNNER_NAME,
# RUNNER_LABELS) is folded in too and takes precedence over the file, e.g.:
#
#   RUNNER_TOKEN=$(gh api -X POST \
#       repos/cratis/automation/actions/runners/registration-token --jq .token)
#   GITHUB_URL=https://github.com/cratis/automation RUNNER_TOKEN=$RUNNER_TOKEN \
#       ./run-local.sh

set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-cratis/gh-runner}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
RUNNER_MODE="${RUNNER_MODE:-actions}"
RUNNER_ENV_FILE="${RUNNER_ENV_FILE:-$HOME/.cratis-gh-runner.env}"

# Merge into a private temp file rather than passing -e flags, so secrets
# never appear in this script's own `docker run` argv either. Shell overrides
# are appended after the file so they win; the awk pass keeps only the last
# occurrence of each key. (Built with awk, not a bash associative array -
# macOS ships bash 3.2 by default, which doesn't have those.)
merged_env_file="$(mktemp)"
chmod 600 "${merged_env_file}"
trap 'rm -f "${merged_env_file}"' EXIT

{
    if [[ -f "${RUNNER_ENV_FILE}" ]]; then
        cat "${RUNNER_ENV_FILE}"
    fi
    for var in GITHUB_URL GITHUB_PAT RUNNER_TOKEN RUNNER_NAME RUNNER_LABELS; do
        if [[ -n "${!var:-}" ]]; then
            printf '%s=%s\n' "${var}" "${!var}"
        fi
    done
} | awk -F= '
    /^[[:space:]]*(#.*)?$/ { next }
    { value = substr($0, length($1) + 2); seen[$1] = value }
    END { for (key in seen) print key "=" seen[key] }
' > "${merged_env_file}"

args=(
    --rm
    -e RUNNER_MODE="${RUNNER_MODE}"
    --env-file "${merged_env_file}"
)

if [[ "${RUNNER_MODE}" == "shell" ]]; then
    args+=(-it)
fi

if [[ "${MOUNT_DOCKER_SOCK:-1}" == "1" && -S /var/run/docker.sock ]]; then
    args+=(-v /var/run/docker.sock:/var/run/docker.sock)
fi

# Not `exec` - exec would replace this shell, so the EXIT trap above would
# never fire and the merged env file (which holds the secrets) would be left
# behind on disk.
docker run "${args[@]}" "${IMAGE_NAME}:${IMAGE_TAG}"
