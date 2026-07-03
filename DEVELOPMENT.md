# Development

This document explains how the `tektoncd-catalog/kaniko` repository is
structured and how to develop, generate, test, and release its Task and
StepAction.

> [!IMPORTANT]
> The `task/` directory is the **source of truth**. The `stepaction/` directory
> is **generated** from it. Never edit `stepaction/kaniko/kaniko.yaml`
> directly — edit the Task and run `./hack/generate-stepaction.sh`.

## Architecture overview

The repository ships a `kaniko` [Task](task/kaniko/) and a derived
[StepAction](stepaction/kaniko/) for Tekton Pipelines. Both use the
`ghcr.io/osscontainertools/kaniko` executor image (the community-maintained
fork of the archived Google kaniko project).

```
task/kaniko/kaniko.yaml  ─────────── (source of truth)
        │
        └─► hack/generate-stepaction.py ──► stepaction/kaniko/kaniko.yaml
                                            (generated — do not edit)
```

Key files:

| Path | Role |
|------|------|
| `task/kaniko/kaniko.yaml` | **Hand-edited.** The `kaniko` Task — the single source of truth. |
| `stepaction/kaniko/kaniko.yaml` | **Generated** from the Task. Do not edit. |
| `hack/generate-stepaction.sh` | Wrapper that runs the Python generator. |
| `hack/generate-stepaction.py` | Derives the StepAction from the Task (workspaces → params). |
| `hack/release.sh` | Release automation: bump version → regenerate → changelog → commit → tag → push. |
| `test/` | e2e runners (`e2e-tests.sh`, `e2e-bundle-test.sh`). |
| `.github/workflows/` | `build.yaml` (lint/e2e), `release.yaml` (bundle publish). |

### Why generate the StepAction?

- **Deterministic:** CI regenerates the StepAction and diffs it against what's
  committed. The committed file must match exactly.
- **DRY:** The StepAction is a mechanical transform of the Task, so behaviour
  stays in lockstep instead of being maintained by hand in two places.

## How generation works

Run:

```bash
./hack/generate-stepaction.sh
```

Requirements: `python3` with **PyYAML**. If PyYAML isn't importable directly,
the wrapper falls back to `uv tool run --with pyyaml`.

`generate-stepaction.py` parses the Task's build step and produces a StepAction:

- **Workspaces become params.** `source` → `source-path`, `dockerconfig` →
  `dockerconfig-path`.
- **Both steps merge into one.** The kaniko executor runs via a script, and the
  URL result is written in the same step.
- **Script references use env vars** (never `$(params.*)`) because `$(params.*)`
  substitution is not allowed in StepAction scripts.

## Modifying the Task or StepAction

1. Edit `task/kaniko/kaniko.yaml`.
2. Regenerate the StepAction:
   ```bash
   ./hack/generate-stepaction.sh
   ```
3. Review both files and commit them together.

## Running tests locally

E2e tests run against a real Tekton install in a local
[kind](https://kind.sigs.k8s.io/) cluster:

```bash
kind create cluster
./test/e2e-tests.sh
./test/e2e-bundle-test.sh
```

Useful environment variables:

| Var | Default | Meaning |
|-----|---------|---------|
| `PIPELINE_VERSION` | `v1.12.0` | Tekton Pipelines release to install |
| `TIMEOUT` | `180s` | Per-TaskRun timeout |
| `BUNDLE_REGISTRY` | `ttl.sh` | Registry the bundle test pushes to |

## Release process

Releases are driven by `hack/release.sh`:

```bash
./hack/release.sh v0.2.0 --dry-run    # preview the diff
./hack/release.sh v0.2.0              # bump, regenerate, commit, tag, push
```

What it does:

1. Validates the version (`vX.Y.Z`) and that you're on an up-to-date `main`.
2. Bumps the `app.kubernetes.io/version` label in the Task and StepAction.
3. Regenerates the StepAction from the bumped Task.
4. Commits (`--signoff`), pushes `main`, creates an annotated tag, and pushes
   the tag.

The tag push triggers `.github/workflows/release.yaml`, which publishes a
Tekton bundle to `ghcr.io/tektoncd-catalog/kaniko`.

## See also

- [CONTRIBUTING.md](CONTRIBUTING.md) — contribution workflow and CI expectations.
