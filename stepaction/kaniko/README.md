# Kaniko StepAction

This StepAction builds source into a container image using
[`kaniko`](https://github.com/osscontainertools/kaniko). It is a composable
step version of the [kaniko Task](../../task/kaniko/README.md).

> **Note:** This file is **generated** from the Task. Do not edit it directly.
> Edit the Task and run `./hack/generate-stepaction.sh`.

## Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `source-path` | Path to the source code containing the Dockerfile and build context. | _(required)_ |
| `dockerconfig-path` | Path to a directory containing a docker `config.json`. | `""` (no auth) |
| `IMAGE` | Name (reference) of the image to build. | _(required)_ |
| `DOCKERFILE` | Path to the Dockerfile to build. | `./Dockerfile` |
| `CONTEXT` | The build context used by Kaniko. | `./` |
| `EXTRA_ARGS` | Additional args to pass to the Kaniko executor. | `[]` |
| `BUILDER_IMAGE` | The Kaniko executor image to use. | `ghcr.io/osscontainertools/kaniko:v1.27.6` |
| `KANIKO_DIR` | Kaniko working directory (buildcontext, stages, layers, caches, docker config). | `/kaniko` |

## Results

| Result | Description |
|--------|-------------|
| `IMAGE_DIGEST` | Digest of the image just built. |
| `IMAGE_URL` | URL of the image just built. |

## Usage

```yaml
apiVersion: tekton.dev/v1
kind: TaskRun
metadata:
  name: kaniko-build
spec:
  taskSpec:
    steps:
      - name: build
        ref:
          name: kaniko
        params:
          - name: source-path
            value: $(workspaces.source.path)
          - name: IMAGE
            value: registry.example.com/my-image:latest
    workspaces:
      - name: source
  workspaces:
    - name: source
      persistentVolumeClaim:
        claimName: my-source
```
