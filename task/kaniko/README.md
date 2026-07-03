# Kaniko

This Task builds source into a container image using
[`kaniko`](https://github.com/osscontainertools/kaniko).

> kaniko doesn't depend on a Docker daemon and executes each command within a
> Dockerfile completely in userspace. This enables building container images in
> environments that can't easily or securely run a Docker daemon, such as a
> standard Kubernetes cluster.

This Task stores the image name and digest as results, allowing
[Tekton Chains](https://github.com/tektoncd/chains) to pick up that an image
was built & sign it.

## Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `IMAGE` | Name (reference) of the image to build. | _(required)_ |
| `DOCKERFILE` | Path to the Dockerfile to build. | `./Dockerfile` |
| `CONTEXT` | The build context used by Kaniko. | `./` |
| `EXTRA_ARGS` | Additional args to pass to the Kaniko executor. | `[]` |
| `BUILDER_IMAGE` | The Kaniko executor image to use. | `ghcr.io/osscontainertools/kaniko:v1.27.6` |
| `KANIKO_DIR` | Kaniko working directory (buildcontext, stages, layers, caches, docker config). | `/kaniko` |

## Workspaces

| Workspace | Description | Optional |
|-----------|-------------|----------|
| `source` | Holds the context and Dockerfile. | No |
| `dockerconfig` | Includes a docker `config.json` for registry auth. | Yes |

## Results

| Result | Description |
|--------|-------------|
| `IMAGE_DIGEST` | Digest of the image just built. |
| `IMAGE_URL` | URL of the image just built. |

## Authentication

To authenticate to a remote container registry, use the `dockerconfig`
workspace bound to a Secret containing a `config.json` key:

```yaml
workspaces:
  - name: dockerconfig
    secret:
      secretName: my-docker-credentials
```

## Usage

```yaml
apiVersion: tekton.dev/v1
kind: TaskRun
metadata:
  name: kaniko-build
spec:
  taskRef:
    name: kaniko
  workspaces:
    - name: source
      persistentVolumeClaim:
        claimName: my-source
  params:
    - name: IMAGE
      value: registry.example.com/my-image:latest
```
