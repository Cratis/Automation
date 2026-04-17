# Workflow Optimization

Patterns we apply on top of the custom runner image to keep CI fast.

## 1. Skip the setup steps

With the toolchain baked in, drop `setup-dotnet`, `setup-node`,
`setup-python`, etc:

```yaml
jobs:
  build:
    runs-on: [self-hosted, linux, cratis]
    steps:
      - uses: actions/checkout@v4
      - run: dotnet build
```

Only add a setup action if you need a version the image doesn't provide.

## 2. Cancel superseded runs

```yaml
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true
```

## 3. Cache the slow caches

Even with a hot image, the first restore on a new PR is expensive. Cache the
package manager stores, not the build output:

```yaml
- uses: actions/cache@v4
  with:
    path: |
      ~/.nuget/packages
      ~/.local/share/pnpm/store
    key: deps-${{ runner.os }}-${{ hashFiles('**/packages.lock.json', '**/pnpm-lock.yaml') }}
    restore-keys: deps-${{ runner.os }}-
```

Use lockfile-based cache keys so cache hits are deterministic.

## 4. Split jobs along the critical path

Matrix-build the legs that run in parallel, keep the dependency restore in one
job, and pass artifacts with `actions/upload-artifact` + `download-artifact`.
Self-hosted runners keep this cheap because artifact I/O is local.

## 5. Use ephemeral runners

`config.sh --ephemeral` (which we do) guarantees each job starts from a clean
slot. Combined with `--replace`, you never accidentally inherit state from a
previous job.

## 6. Prefer `runs-on` groups over individual labels

```yaml
runs-on:
  group: cratis
  labels: [linux]
```

Makes it easier to re-route traffic (e.g. to bigger VMs) without changing
workflows.

## 7. Monitor

Every month, sample a handful of `GITHUB_REF`s and compare:

```bash
gh run list -L 50 --json databaseId,name,conclusion,createdAt,updatedAt \
    | jq '.[] | .duration = ((.updatedAt|fromdateiso8601) - (.createdAt|fromdateiso8601)) | {name, conclusion, duration}'
```

If median build time creeps up, revisit the image - usually a new SDK version
or a chatty new step is the cause.

## 8. Budget for cold starts

A fresh VM pulling the runner image adds ~20 s. Keep a warm pool of 1-2
runners up (ARC's `minRunners: 1`) so PR bursts don't cold-start every time.
