# GitHub Configuration

Use this guide when you administer the image or the machines that will accept jobs for repositories in the `cratis` org. [Build and inspect the image locally](local-setup.md) first. Publishing to GHCR lets other hosts pull it; it is not required to run the locally built image. Repository and organization runners are alternatives, not successive deployment steps.

Choose the trust boundary before registering a runner. Never run public-repository `pull_request` jobs on self-hosted infrastructure. Restrict organization runners to the repositories that may use the host, and remember that mounting its Docker socket gives their jobs root-level host control. Publishing a Public image does not change those restrictions.

## 1. Publish the image to GHCR

`Source/GitHub/workflows/publish-runner-image.yml` is a template, not an installed workflow in this repository. After you copy it into `.github/workflows/publish-runner-image.yml`, it builds and pushes to `ghcr.io/<owner>/gh-runner` for changes to `Source/GitHub/**` or the installed workflow on `main`; it also supports manual dispatch. The publishing job requests `contents: read` and `packages: write` for its `GITHUB_TOKEN`.

One-time setup:

1. Copy the workflow into `.github/workflows/publish-runner-image.yml` of this
   repo.
2. Under **Repo Settings -> Actions -> General**, check that repository and organization policy allow the publishing job's explicit `packages: write` permission. Keep the job's `contents: read` and `packages: write` declarations; do not broaden the default token permissions to grant unrelated write access.
3. After the first successful run, open the package at
   `https://github.com/orgs/cratis/packages/container/gh-runner`, go to
   *Package settings*, and:
   - Set visibility to **Internal** (or Public if you want forks to pull it).
   - Link it to the `automation` repo.

The expected result is a published package that the intended runner host can pull. A private image needs pull authorization on that host before it can start a container; runner registration happens only after the container starts.

## 2. Register runners

### Option A - Repository runners

For a single repo, use `Source/GitHub/run-local.sh` on a Linux host with Docker and follow [local setup](local-setup.md) for the protected credential file. The helper defaults to the locally built image; set `IMAGE_NAME` when using a published image instead. Each registration accepts one job in **ephemeral** mode, after which the entrypoint attempts cleanup. Registration lifetime does not make the host disposable.

### Option B - Organization runners (recommended)

1. Go to **Org settings -> Actions -> Runners -> New self-hosted runner**.
2. Generate an org-level registration token using an account authorized to administer organization runners. Use this token directly: the image's PAT exchange calls the repository registration endpoint, not the organization endpoint.
3. Create `~/.cratis-gh-runner.env` with `chmod 600`, then put `GITHUB_URL=https://github.com/cratis`, the org-level `RUNNER_TOKEN` and `RUNNER_LABELS=self-hosted,linux,cratis` in it. Do not put token values in Docker command arguments. From a checkout containing the helper, start the published image:

   ```bash
   cd Source/GitHub
   IMAGE_NAME=ghcr.io/cratis/gh-runner ./run-local.sh
   ```

4. In **Org settings -> Actions -> Runner groups**, create a `cratis` group,
   restrict it to the repos that should be allowed to target these runners,
   and add the new runners to it.

### Option C - Kubernetes (for scale)

For a Kubernetes deployment, start with [Actions Runner Controller](https://github.com/actions/actions-runner-controller). The `AutoscalingRunnerSet` below places the image at `spec.template.spec.containers[].image`, but it is a configuration sketch, not a complete deployment.

The image's entrypoint still requires `GITHUB_URL` and either `RUNNER_TOKEN` or a repository `GITHUB_PAT`. This sketch names `githubConfigSecret` for the controller but does not show those environment variables reaching the container. Resolve that credential wiring and controller compatibility before using this route; the example alone does not establish a working integration.

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

For a trusted private-repository workflow, match its `runs-on` labels to the labels on an online runner. Do not apply this change to public-repository `pull_request` jobs. Replace:

```yaml
runs-on: ubuntu-latest
```

with:

```yaml
runs-on: [self-hosted, linux, cratis]
```

The [consumer CI example](../../Source/GitHub/workflows/ci.yml) uses these labels and runs restore, Release build and tests. It illustrates runner selection, not a public-PR-safe hosting policy. If a job stays queued, use [the label and status checks](troubleshooting.md#workflows-queue-forever) before changing the workflow again.

## 4. Secrets and variables

Configure organization secrets for the operations your workflows and hosts need, and restrict repository access to them. The existing names distinguish private-image pulls from package publishing:

| Name                | Purpose                                       |
| ------------------- | --------------------------------------------- |
| `GHCR_PULL_TOKEN`   | If the image is private, for hosts that pull  |
| `NUGET_API_KEY`     | Publishing NuGet packages                     |

The job uses its per-run `GITHUB_TOKEN` for repository access, with permissions set by the workflow and allowed policy. This does not replace the credential needed to register a runner or the host's authorization to pull a private image. Keep those credentials in their respective protected setup paths.

## 5. Security considerations

- Do not run public-repository pull-request jobs on self-hosted runners: fork code must not execute on this infrastructure. Check which repositories and workflows can target the runner rather than assuming this repository's visibility makes the host safe.
- `--ephemeral` limits a runner registration to one job. It does not isolate a compromised job from the host or make a Compose restart use a fresh filesystem.
- Pin the image by digest in production:
  `image: ghcr.io/cratis/gh-runner@sha256:...`
- The Docker socket mount gives workflows root on the host. If that trust is unacceptable, do not start a socket-mounted runner. Rootless Docker in the container or `buildkitd` as a sidecar requires separate setup; neither is configured automatically by this image. See [local socket-mount controls](local-setup.md#docker-in-docker-vs-socket-mount) before choosing a host.
