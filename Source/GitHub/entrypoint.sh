#!/usr/bin/env bash
# Entrypoint for the Cratis custom GitHub Actions runner image.
#
# Modes:
#   RUNNER_MODE=actions (default) - Register and run as an ephemeral self-hosted
#                                   GitHub Actions runner.
#   RUNNER_MODE=copilot            - Start an interactive shell. Copilot coding
#                                   agent drives the container itself.
#   RUNNER_MODE=shell              - Drop into bash for local debugging.

set -euo pipefail

: "${RUNNER_MODE:=actions}"

log() { printf '[entrypoint] %s\n' "$*"; }

register_and_run_actions_runner() {
    : "${GITHUB_URL:?GITHUB_URL is required (e.g. https://github.com/cratis/automation)}"

    if [[ -n "${RUNNER_TOKEN:-}" ]]; then
        token="${RUNNER_TOKEN}"
    elif [[ -n "${GITHUB_PAT:-}" ]]; then
        log "Exchanging GITHUB_PAT for an ephemeral registration token"
        repo_path="${GITHUB_URL#https://github.com/}"
        token=$(curl -fsSL -X POST \
            -H "Accept: application/vnd.github+json" \
            -H "Authorization: Bearer ${GITHUB_PAT}" \
            -H "X-GitHub-Api-Version: 2022-11-28" \
            "https://api.github.com/repos/${repo_path}/actions/runners/registration-token" \
            | jq -r .token)
    else
        echo "Provide RUNNER_TOKEN or GITHUB_PAT" >&2
        exit 1
    fi

    runner_name="${RUNNER_NAME:-cratis-$(hostname)-$(date +%s)}"
    runner_labels="${RUNNER_LABELS:-self-hosted,linux,cratis}"

    log "Configuring runner '${runner_name}' against ${GITHUB_URL}"
    ./config.sh \
        --url "${GITHUB_URL}" \
        --token "${token}" \
        --name "${runner_name}" \
        --labels "${runner_labels}" \
        --work "_work" \
        --unattended \
        --ephemeral \
        --replace

    cleanup() {
        log "Removing runner registration"
        ./config.sh remove --token "${token}" || true
    }
    trap cleanup EXIT INT TERM

    log "Starting runner"
    exec ./run.sh
}

case "${RUNNER_MODE}" in
    actions)  register_and_run_actions_runner ;;
    copilot)  log "Copilot mode - container ready"; exec sleep infinity ;;
    shell)    exec bash ;;
    *)        echo "Unknown RUNNER_MODE: ${RUNNER_MODE}" >&2; exit 2 ;;
esac
