# Kaniko Task for Tekton

[![Artifact Hub Tasks](https://img.shields.io/endpoint?url=https://artifacthub.io/badge/repository/tekton-kaniko-tasks)](https://artifacthub.io/packages/search?repo=tekton-kaniko-tasks)
[![Artifact Hub StepActions](https://img.shields.io/endpoint?url=https://artifacthub.io/badge/repository/tekton-kaniko-stepactions)](https://artifacthub.io/packages/search?repo=tekton-kaniko-stepactions)

This repository contains the `kaniko` [Task](task/kaniko/) and [StepAction](stepaction/kaniko/) for [Tekton Pipelines](https://tekton.dev/), providing container image building capabilities using [kaniko](https://github.com/osscontainertools/kaniko).

> **Note:** This uses the community-maintained fork of kaniko
> ([osscontainertools/kaniko](https://github.com/osscontainertools/kaniko))
> since the original Google repository was archived.

## Installation

Install the Task directly:

```bash
kubectl apply -f https://raw.githubusercontent.com/tektoncd-catalog/kaniko/main/task/kaniko/kaniko.yaml
```

Or use a [Tekton Bundle](https://tekton.dev/docs/pipelines/tekton-bundle-contracts/) with the bundle resolver:

```yaml
taskRef:
  resolver: bundles
  params:
    - name: bundle
      value: ghcr.io/tektoncd-catalog/kaniko/bundle:v0.1.0
    - name: name
      value: kaniko
    - name: kind
      value: task
```

## Quick Start

```yaml
apiVersion: tekton.dev/v1
kind: TaskRun
metadata:
  generateName: kaniko-build-
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

## Documentation

- **[Task reference](task/kaniko/README.md)** — full parameter, workspace, and authentication docs
- **[StepAction reference](stepaction/kaniko/README.md)** — composable step version
- **[DEVELOPMENT.md](DEVELOPMENT.md)** — architecture, generation, testing, and release process
- **[CONTRIBUTING.md](CONTRIBUTING.md)** — contribution workflow and CI expectations
