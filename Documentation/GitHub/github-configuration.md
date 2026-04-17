# GitHub Configuration

How to register the custom runner with GitHub and publish the image so other
repos in the `cratis` org can reuse it.

## 1. Publish the image to GHCR

The `Source/GitHub/workflows/publish-runner-image.yml` workflow builds and
pushes the image to `ghcr.io/<owner>/gh-runner` on every change to
`Source/GitHub/**` on `main`.

One-time setup:

1. Copy the workflow into `.github/workflows/publish-runner-image.yml` of this
   repo.
2. Under **Repo Settings -> Actions -> General**, enable
   *Read and write permissions* for `GITHUB_TOKEN` (required for GHCR push).
3. After the first successful run, open the package at
   `https://github.com/orgs/cratis/packages/container/gh-runner`, go to
   *Package settings*, and:
   - Set visibility to **Internal** (or Public if you want forks to pull it).
   - Link it to the `automation` repo.

## 2. Register runners

### Option A - Repository runners

For a single repo (including this one), use the script in
`Source/GitHub/run-local.sh` on any Linux host with Docker. Each container
registers as an **ephemeral** runner and is removed after one job.

### Option B - Organization runners (recommended)

1. Go to **Org settings -> Actions -> Runners -> New self-hosted runner**.
2. Generate an org-level registration token.
3. Pass it to the container:

   ```bash
   GITHUB_URL=https://github.com/cratis \
   RUNNER_TOKEN=<token> \
   RUNNER_LABELS=self-hosted,linux,cratis \
   docker run --rm \
       -e GITHUB_URL -e RUNNER_TOKEN -e RUNNER_LABELS \
       -v /var/run/docker.sock:/var/run/docker.sock \
       ghcr.io/cratis/gh-runner:latest
   ```

4. In **Org settings -> Actions -> Runner groups**, create a `cratis` group,
   restrict it to the repos that should be allowed to target these runners,
   and add the new runners to it.

### Option C - Kubernetes (for scale)

Use [Actions Runner Controller](https://github.com/actions/actions-runner-controller)
with our image as the `spec.template.spec.containers[].image`. A minimal
`AutoscalingRunnerSet`:

```yaml
apiVersion: actions.github.com/v1alpha1
kind: AutoscalingRunnerSet
metadata:
  name: cratis-runners
  namespace: arc-runners
spec:
  githubConfigUrl: https://github.com/cratis
  githubConfigSecret: arc-github-secret
  minRunners: 1
  maxRunners: 20
  template:
    spec:
      containers:
        - name: runner
          image: ghcr.io/cratis/gh-runner:latest
          command: ["/home/runner/entrypoint.sh"]
          env:
            - { name: RUNNER_MODE, value: actions }
```

## 3. Target the runners from workflows

In any workflow, replace:

```yaml
runs-on: ubuntu-latest
```

with:

```yaml
runs-on: [self-hosted, linux, cratis]
```

See `Source/GitHub/workflows/ci.yml` for a full example.

## 4. Secrets and variables

At org level, set:

| Name                | Purpose                                       |
| ------------------- | --------------------------------------------- |
| `GHCR_PULL_TOKEN`   | If the image is private, for hosts that pull  |
| `NUGET_API_KEY`     | Publishing NuGet packages                     |

Nothing else is required - the runner uses the job's per-run `GITHUB_TOKEN`
for repository access.

## 5. Security considerations

- Never attach self-hosted runners to **public** repos without extra sandboxing
  - forks can submit workflow changes that execute on your infrastructure.
  This repo is internal, so it's fine.
- Use `--ephemeral` (we do) so one compromised job cannot affect the next.
- Pin the image by digest in production:
  `image: ghcr.io/cratis/gh-runner@sha256:...`
- The Docker socket mount gives workflows root on the host. If that's too
  much trust, switch to rootless Docker in the container or to `buildkitd`
  running as a sidecar.
