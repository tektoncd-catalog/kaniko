# AGENTS.md

Guidance for AI coding agents working in `tektoncd-catalog/kaniko`. For full
detail see [DEVELOPMENT.md](DEVELOPMENT.md).

## Repository structure

| Path | Role |
|------|------|
| `task/kaniko/kaniko.yaml` | **Edit this.** The `kaniko` Task — the single source of truth. |
| `stepaction/kaniko/kaniko.yaml` | **Generated — never edit by hand.** Derived from the Task. |
| `hack/generate-stepaction.sh` | Wrapper around the Python generator. |
| `hack/generate-stepaction.py` | Derives the StepAction from the Task (workspaces → params). |
| `hack/release.sh` | Release automation. |
| `test/` | e2e runners (`e2e-tests.sh`, `e2e-bundle-test.sh`). |
| `.github/workflows/` | `build.yaml` (lint/e2e), `release.yaml` (bundle publish). |

## Critical Rules

1. **Never edit `stepaction/kaniko/kaniko.yaml` directly.** It is generated
   from the Task. Edit `task/kaniko/kaniko.yaml`, then run
   `./hack/generate-stepaction.sh`. CI's lint step diffs the committed file
   against a freshly generated one and fails on mismatch.
2. **No `$(params.*)` in `script:` blocks.** For StepActions `$(params.*)` in
   scripts is not supported. Pass values via `env:` and reference the shell
   env var.
3. **Workspaces map to params in the StepAction.** `source` → `source-path`,
   `dockerconfig` → `dockerconfig-path`.
4. **Sign off every commit** (DCO / EasyCLA): `git commit --signoff`.
5. **Use conventional commit prefixes** (`feat:`, `fix:`, `docs:`, `chore:`,
   `ci:`) — the release changelog is derived from them.

## Common commands

```bash
./hack/generate-stepaction.sh          # regenerate the StepAction from the Task
./hack/release.sh v0.2.0 --dry-run    # preview a release
./test/e2e-tests.sh                    # e2e in a kind cluster
./test/e2e-bundle-test.sh              # bundle-resolver e2e
```

## Validating changes locally

1. After editing the Task, run `./hack/generate-stepaction.sh`.
2. Confirm `git status` shows only intended changes.
3. Run the relevant e2e script against a kind cluster.
4. Update `README.md` if you changed installation or usage.
