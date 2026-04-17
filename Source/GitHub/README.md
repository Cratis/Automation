# Source/GitHub

Custom GitHub Actions runner image for Cratis, plus the workflows that build,
publish, and consume it.

## Contents

| Path                               | Purpose                                                          |
| ---------------------------------- | ---------------------------------------------------------------- |
| `Dockerfile`                       | Ubuntu-based image with .NET, Node, pnpm, Python, Go, gh, Docker |
| `entrypoint.sh`                    | Registers an ephemeral runner or starts Copilot/shell mode       |
| `build.sh`                         | Local image build helper                                         |
| `run-local.sh`                     | Local container run helper                                       |
| `docker-compose.yml`               | Run one or more local runners                                    |
| `copilot-setup-steps.yml`          | Copilot coding-agent environment bootstrap                       |
| `workflows/ci.yml`                 | Sample consumer CI workflow using the self-hosted runner         |
| `workflows/publish-runner-image.yml` | Builds and publishes the image to GHCR                         |

See `Documentation/GitHub/` for full setup and usage instructions.
