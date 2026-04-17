#!/usr/bin/env bash
# Build the custom GitHub Actions runner image locally.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_NAME="${IMAGE_NAME:-cratis/gh-runner}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
PLATFORM="${PLATFORM:-linux/amd64}"

docker buildx build \
    --platform "${PLATFORM}" \
    --tag "${IMAGE_NAME}:${IMAGE_TAG}" \
    --load \
    "${SCRIPT_DIR}"

echo "Built ${IMAGE_NAME}:${IMAGE_TAG} for ${PLATFORM}"
