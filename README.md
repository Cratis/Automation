# Cratis Automation

Infrastructure and tooling that supports the Cratis development loop.

## Layout

```
.
├── Source/
│   └── GitHub/          Custom GitHub Actions runner image + related workflows
└── Documentation/
    └── GitHub/          How to build, run, and integrate the runner and Copilot
```

## Running a local agent

The "agent" is our custom GitHub Actions self-hosted runner image - a Docker
image with .NET, Node, pnpm, Python, Go, and the GitHub CLI pre-installed. You
build it once, then register it against either a single repository or an
entire GitHub organization.

### 1. Build the image

```bash
cd Source/GitHub
./build.sh
```

Override `IMAGE_NAME`, `IMAGE_TAG`, or `PLATFORM` via environment variables.
Requires Docker 24+ with Buildx. See below if you're on Apple Silicon.

### Apple Silicon (ARM64)

The Dockerfile detects its architecture at build time (`dpkg
--print-architecture`) and pulls the matching arm64 binaries for the GitHub
Actions runner and Go automatically - no changes needed to build or run an
arm64 image.

On an M-series Mac, build natively for arm64 instead of the `linux/amd64`
default:

```bash
PLATFORM=linux/arm64 ./build.sh
```

Building/running the default `linux/amd64` image still works under Docker
Desktop's emulation, but it's noticeably slower to build and to execute jobs
- prefer the native arm64 build above.

`run-local.sh` and `docker-compose.yml` don't pin a platform themselves; they
just run whatever `IMAGE_NAME:IMAGE_TAG` you built and loaded locally, so
once you've built with `PLATFORM=linux/arm64`, `./run-local.sh` and
`docker compose up` work unmodified.

If you run both amd64 and arm64 agents against the same repo/org, consider
adding an arch label (e.g. `RUNNER_LABELS=self-hosted,linux,arm64,cratis`) so
workflows can target one or the other with `runs-on`.

The multi-arch publish workflow
(`Source/GitHub/workflows/publish-runner-image.yml`, which builds both
`linux/amd64` and `linux/arm64`) also runs fine from an Apple Silicon host -
Docker Desktop ships the QEMU/binfmt setup needed to cross-build the amd64
leg under emulation.

### 2. Get a GitHub token

The agent needs a token to register itself as a runner - either a personal
access token (PAT), which it exchanges for a short-lived registration token,
or a registration token you generate yourself.

**Classic PAT** (simplest; works for both repo- and org-level registration)

1. GitHub -> your avatar -> **Settings** -> **Developer settings** ->
   **Personal access tokens** -> **Tokens (classic)** -> **Generate new
   token (classic)**.
2. Select scopes:
   - `repo` + `workflow` - for repo-level registration (step 3 below).
   - `admin:org` - for org-level registration (step 4 below).
3. Set an expiration, generate, and copy the token immediately - GitHub only
   shows it once. Use it as `GITHUB_PAT`.

**Fine-grained PAT** (narrower scope; repo-level registration)

1. GitHub -> your avatar -> **Settings** -> **Developer settings** ->
   **Personal access tokens** -> **Fine-grained tokens** -> **Generate new
   token**.
2. Set **Resource owner** to the org, and **Repository access** to the
   specific repo (or a chosen set of repos).
3. Under **Repository permissions**, grant **Actions: Read and write** and
   **Administration: Read and write**.
4. Generate and copy the token. Use it as `GITHUB_PAT`.

Fine-grained tokens can also be scoped to organization permissions (**Self-
hosted runners: Read and write**) for org-level registration, but only if
your org allows fine-grained PAT access to org resources - many orgs
restrict this. If yours does, or if you'd rather skip PATs entirely, generate
a registration token directly instead and pass it as `RUNNER_TOKEN`:

```bash
# Repo-level (needs a token/gh session with access to the repo):
gh api -X POST repos/<owner>/<repo>/actions/runners/registration-token --jq .token

# Org-level (needs a token/gh session with admin:org, e.g. `gh auth refresh -s admin:org`):
gh api -X POST orgs/<org>/actions/runners/registration-token --jq .token
```

Registration tokens expire after about an hour, so generate one right before
running the agent.

### 3. Configure per repository

Register the agent against a single repo with a PAT (`repo` + `workflow`
scopes):

```bash
export GITHUB_URL=https://github.com/<owner>/<repo>
export GITHUB_PAT=ghp_xxxxxxxxxxxxxxxx
./run-local.sh
```

Or exchange a repo-scoped registration token yourself and skip the PAT:

```bash
RUNNER_TOKEN=$(gh api -X POST \
    repos/<owner>/<repo>/actions/runners/registration-token --jq .token)
GITHUB_URL=https://github.com/<owner>/<repo> RUNNER_TOKEN=$RUNNER_TOKEN \
    ./run-local.sh
```

Each container registers as an **ephemeral** runner (one job, then it
deregisters). Run several at once with `docker compose up --scale runner=N`.

### 4. Configure per organization

Register against the whole org so any repo in it can target the agent. Get an
org-level registration token either from **Org settings -> Actions -> Runners
-> New self-hosted runner** in the GitHub UI, or via:

```bash
RUNNER_TOKEN=$(gh api -X POST \
    orgs/<org>/actions/runners/registration-token --jq .token)
```

Then run:

```bash
export GITHUB_URL=https://github.com/<org>
export RUNNER_TOKEN=<org-level-registration-token>
export RUNNER_LABELS=self-hosted,linux,cratis
./run-local.sh
```

In **Org settings -> Actions -> Runner groups**, create a group, restrict it
to the repos allowed to use these agents, and add the new runner to it - this
is what scopes an org-registered agent down to specific repos.

### Other run modes

- `RUNNER_MODE=shell ./run-local.sh` - interactive shell for debugging the
  image, no registration.
- `RUNNER_MODE=copilot ./run-local.sh` - idles so you can `docker exec` into
  it the way the Copilot coding agent does.

Full details, including Kubernetes/Actions Runner Controller for scale, in
[`Documentation/GitHub/local-setup.md`](Documentation/GitHub/local-setup.md)
and
[`Documentation/GitHub/github-configuration.md`](Documentation/GitHub/github-configuration.md).

## Start here

- [`Documentation/GitHub/README.md`](Documentation/GitHub/README.md) - overview
- [`Documentation/GitHub/local-setup.md`](Documentation/GitHub/local-setup.md) - run locally
- [`Documentation/GitHub/github-configuration.md`](Documentation/GitHub/github-configuration.md) - wire up in GitHub
- [`Documentation/GitHub/copilot-agent.md`](Documentation/GitHub/copilot-agent.md) - run Copilot on assigned issues
