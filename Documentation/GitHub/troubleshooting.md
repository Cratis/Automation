# Troubleshooting

## The runner never comes online

1. Check the container logs: `docker logs <container>`.
2. Common causes:
   - PAT missing scopes - needs `repo` and `workflow`.
   - Org runners require the PAT/registration token to be **org-level**, not
     repo-level.
   - Network egress blocked - the runner must reach
     `https://api.github.com`, `https://pipelines.actions.githubusercontent.com`,
     and `https://objects.githubusercontent.com`.

## Workflows queue forever

The `runs-on` labels don't match any active runner. Double-check:

```bash
gh api repos/cratis/automation/actions/runners | jq '.runners[] | {name, status, labels: [.labels[].name]}'
```

Every label in the workflow's `runs-on` list must appear on at least one
**online**, **idle** runner.

## Docker build steps fail with "permission denied on /var/run/docker.sock"

The socket was mounted but the `runner` user isn't in the `docker` group
inside the container. Quick fix - add to `Dockerfile` after the `useradd`
line:

```dockerfile
RUN groupadd -f -g $(stat -c '%g' /var/run/docker.sock 2>/dev/null || echo 999) docker \
    && usermod -aG docker runner
```

Even better: run Buildkit as a sidecar and avoid the socket mount altogether.

## Copilot PRs come up with the wrong toolchain

`copilot-setup-steps.yml` is either missing, misnamed, or failing. Verify:

```bash
gh workflow view copilot-setup-steps.yml
gh run list --workflow=copilot-setup-steps.yml -L 5
```

The job inside the workflow must be named exactly `copilot-setup-steps`.

## "Token not authorized" when publishing to GHCR

The `publish-runner-image` workflow needs `permissions: packages: write` and
the repo's default token permissions must allow write. Set under
**Repo settings -> Actions -> General -> Workflow permissions**.

## Ephemeral runner leaves a ghost entry

If a host is killed mid-job, the runner can't deregister. Clean it up:

```bash
gh api -X GET repos/cratis/automation/actions/runners \
    | jq '.runners[] | select(.status=="offline") | .id' \
    | xargs -I{} gh api -X DELETE repos/cratis/automation/actions/runners/{}
```
