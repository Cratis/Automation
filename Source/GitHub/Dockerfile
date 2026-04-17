# syntax=docker/dockerfile:1.7

# Custom GitHub Actions runner image for Cratis/Automation.
#
# Two roles in one image:
#   1. A self-hosted GitHub Actions runner with common Cratis tooling pre-installed,
#      so workflows skip slow "install X" steps on every run.
#   2. A ready-made environment for GitHub Copilot coding agent (Copilot-assigned
#      issues) so the agent starts in a fully bootstrapped workspace.

ARG RUNNER_VERSION=2.320.0
ARG DOTNET_VERSION=10.0
ARG NODE_VERSION=24
ARG PNPM_VERSION=10.2.0
ARG GO_VERSION=1.23.4
ARG PYTHON_VERSION=3.12

FROM ubuntu:24.04

ARG RUNNER_VERSION
ARG DOTNET_VERSION
ARG NODE_VERSION
ARG PNPM_VERSION
ARG GO_VERSION
ARG PYTHON_VERSION
ARG TARGETARCH

ENV DEBIAN_FRONTEND=noninteractive \
    RUNNER_ALLOW_RUNASROOT=0 \
    DOTNET_CLI_TELEMETRY_OPTOUT=1 \
    DOTNET_NOLOGO=1 \
    NUGET_XMLDOC_MODE=skip \
    PATH=/usr/local/go/bin:/home/runner/.dotnet/tools:/usr/local/dotnet:$PATH \
    DOTNET_ROOT=/usr/local/dotnet \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

# Base OS packages and build toolchain.
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl wget gnupg lsb-release software-properties-common \
        git git-lfs jq unzip zip xz-utils zstd \
        build-essential pkg-config make cmake \
        openssh-client sudo locales tzdata \
        libssl-dev libicu-dev libkrb5-3 zlib1g \
        iputils-ping netcat-openbsd dnsutils \
    && locale-gen C.UTF-8 \
    && rm -rf /var/lib/apt/lists/*

# GitHub CLI.
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        | gpg --dearmor -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/*

# Docker CLI + Buildx + Compose plugin (for docker-outside-of-docker scenarios).
RUN install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
        | gpg --dearmor -o /etc/apt/keyrings/docker.gpg \
    && chmod a+r /etc/apt/keyrings/docker.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release; echo $VERSION_CODENAME) stable" \
        > /etc/apt/sources.list.d/docker.list \
    && apt-get update && apt-get install -y --no-install-recommends \
        docker-ce-cli docker-buildx-plugin docker-compose-plugin \
    && rm -rf /var/lib/apt/lists/*

# .NET SDK (channel-based install via official script).
RUN curl -fsSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh \
    && chmod +x /tmp/dotnet-install.sh \
    && /tmp/dotnet-install.sh --channel ${DOTNET_VERSION} --install-dir ${DOTNET_ROOT} \
    && rm /tmp/dotnet-install.sh \
    && ln -s ${DOTNET_ROOT}/dotnet /usr/local/bin/dotnet

# Node.js + pnpm (corepack) + yarn.
RUN curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && corepack enable \
    && corepack prepare pnpm@${PNPM_VERSION} --activate \
    && corepack prepare yarn@stable --activate \
    && rm -rf /var/lib/apt/lists/*

# Python.
RUN apt-get update && apt-get install -y --no-install-recommends \
        python${PYTHON_VERSION} python${PYTHON_VERSION}-venv python3-pip \
    && ln -sf /usr/bin/python${PYTHON_VERSION} /usr/local/bin/python \
    && ln -sf /usr/bin/python${PYTHON_VERSION} /usr/local/bin/python3 \
    && rm -rf /var/lib/apt/lists/*

# Go.
RUN set -eux; \
    arch="$(dpkg --print-architecture)"; \
    case "$arch" in \
        amd64)  go_arch=amd64  ;; \
        arm64)  go_arch=arm64  ;; \
        *) echo "unsupported arch: $arch" >&2; exit 1 ;; \
    esac; \
    curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-${go_arch}.tar.gz" \
        | tar -C /usr/local -xz

# Non-root runner user.
RUN useradd -m -u 1001 -s /bin/bash runner \
    && echo "runner ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/runner \
    && chmod 0440 /etc/sudoers.d/runner \
    && mkdir -p /home/runner/actions-runner /home/runner/_work \
    && chown -R runner:runner /home/runner

USER runner
WORKDIR /home/runner/actions-runner

# GitHub Actions self-hosted runner binary.
RUN set -eux; \
    arch="$(dpkg --print-architecture)"; \
    case "$arch" in \
        amd64)  runner_arch=x64    ;; \
        arm64)  runner_arch=arm64  ;; \
        *) echo "unsupported arch: $arch" >&2; exit 1 ;; \
    esac; \
    curl -fsSL -o runner.tar.gz \
        "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-${runner_arch}-${RUNNER_VERSION}.tar.gz"; \
    tar -xzf runner.tar.gz; \
    rm runner.tar.gz

# Warm up the .NET NuGet fallback folder so common restores are fast.
RUN dotnet --info && dotnet help > /dev/null

COPY --chown=runner:runner entrypoint.sh /home/runner/entrypoint.sh
RUN chmod +x /home/runner/entrypoint.sh

ENTRYPOINT ["/home/runner/entrypoint.sh"]
