#!/usr/bin/env bash

# Copyright 2025 The Tekton Authors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# E2e test runner for the kaniko task.
# Installs the task, runs a test TaskRun that builds an image, and waits for
# completion.
#
# Environment variables:
#   PIPELINE_VERSION  - Tekton Pipelines version to install (default: v1.12.0)
#   TIMEOUT           - Timeout for each TaskRun (default: 180s)

set -euo pipefail

PIPELINE_VERSION="${PIPELINE_VERSION:-v1.12.0}"
TIMEOUT="${TIMEOUT:-180s}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "--- Installing Tekton Pipelines ${PIPELINE_VERSION}"
kubectl apply --filename "https://github.com/tektoncd/pipeline/releases/download/${PIPELINE_VERSION}/release.yaml"
echo "--- Waiting for Tekton Pipelines to be ready"
kubectl wait --for=condition=available --timeout=300s \
    deployment --all -n tekton-pipelines
echo "--- Waiting for the admission webhook to serve"
for _ in $(seq 1 30); do
    if [[ -n "$(kubectl get endpoints tekton-pipelines-webhook \
        -n tekton-pipelines -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null)" ]]; then
        break
    fi
    sleep 5
done

echo "--- Installing kaniko task"
kubectl apply -f "${ROOT_DIR}/task/kaniko/kaniko.yaml"

echo "--- Setting up in-cluster registry"
kubectl run registry --image=registry:2 --port=5000
kubectl wait --for=condition=Ready --timeout=60s pod/registry
kubectl expose pod registry --port=5000

echo "--- Creating test TaskRun"
cat <<'EOF' | kubectl apply -f -
apiVersion: tekton.dev/v1
kind: TaskRun
metadata:
  name: kaniko-e2e-test
spec:
  taskRef:
    name: kaniko
  timeout: "0h3m0s"
  workspaces:
    - name: source
      emptyDir: {}
  params:
    - name: IMAGE
      value: registry:5000/kaniko-test:e2e
    - name: EXTRA_ARGS
      value:
        - --insecure
  stepTemplate:
    volumeMounts:
      - name: dockerfile
        mountPath: /workspace/source
  volumes:
    - name: dockerfile
      emptyDir: {}
  podTemplate:
    securityContext:
      runAsUser: 0
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: kaniko-test-dockerfile
data:
  Dockerfile: |
    FROM alpine:3.21
    RUN echo "hello from kaniko e2e test" > /hello.txt
    CMD ["cat", "/hello.txt"]
EOF

# Patch the TaskRun to create the Dockerfile in the workspace via an init step
# Since we can't easily inject files into emptyDir, we use a simpler approach:
# create a PipelineRun that first creates the Dockerfile, then runs kaniko.
kubectl delete taskrun kaniko-e2e-test --ignore-not-found 2>/dev/null || true

echo "--- Creating test PipelineRun with source prep"
cat <<'EOF' | kubectl apply -f -
apiVersion: tekton.dev/v1
kind: PipelineRun
metadata:
  name: kaniko-e2e-test
spec:
  pipelineSpec:
    workspaces:
      - name: shared-workspace
    tasks:
      - name: create-dockerfile
        workspaces:
          - name: source
            workspace: shared-workspace
        taskSpec:
          workspaces:
            - name: source
          steps:
            - name: create
              image: alpine:3.21
              script: |
                cat > $(workspaces.source.path)/Dockerfile <<DOCKERFILE
                FROM alpine:3.21
                RUN echo "hello from kaniko e2e test" > /hello.txt
                CMD ["cat", "/hello.txt"]
                DOCKERFILE
      - name: build
        runAfter: ["create-dockerfile"]
        taskRef:
          name: kaniko
        workspaces:
          - name: source
            workspace: shared-workspace
        params:
          - name: IMAGE
            value: registry:5000/kaniko-test:e2e
          - name: EXTRA_ARGS
            value:
              - --insecure
  workspaces:
    - name: shared-workspace
      volumeClaimTemplate:
        spec:
          accessModes:
            - ReadWriteOnce
          resources:
            requests:
              storage: 256Mi
EOF

sleep 5

SNAP_DIR="$(mktemp -d)"
snapshot_run() {
    kubectl get pipelinerun/"$1" -o yaml --show-managed-fields=false 2>/dev/null \
        | sed -e '/^status:/,$d' \
              -e '/^  resourceVersion:/d' \
              -e '/^  uid:/d' \
              -e '/^  creationTimestamp:/d' \
              -e '/^  generation:/d' \
              -e '/^  selfLink:/d' \
        > "${SNAP_DIR}/$1.yaml"
}

wait_for_run() {
    kubectl wait --for=condition=Succeeded --timeout="${TIMEOUT}" pipelinerun/"$1" 2>/dev/null
}

dump_run() {
    echo "  --- PipelineRun status ---"
    kubectl get pipelinerun/"$1" -o jsonpath='{.status.conditions[*].message}' 2>/dev/null || true
    echo ""
    echo "  --- TaskRun details ---"
    kubectl get taskrun -l tekton.dev/pipelineRun="$1" \
        -o custom-columns='NAME:.metadata.name,STATUS:.status.conditions[0].reason,MESSAGE:.status.conditions[0].message' 2>/dev/null || true
    echo ""
    echo "  --- Pod logs ---"
    for pod in $(kubectl get pods -l tekton.dev/pipelineRun="$1" -o name 2>/dev/null); do
        echo "  >> ${pod}"
        kubectl logs "${pod}" --all-containers 2>/dev/null || true
    done
    echo "  ---"
}

pr="kaniko-e2e-test"
snapshot_run "${pr}"

echo "--- Waiting for PipelineRun to complete (timeout: ${TIMEOUT})"
echo -n "  ${pr} ... "
if wait_for_run "${pr}"; then
    echo "PASSED"
else
    # Retry once for transient flakes
    echo -n "FLAKY, retrying ... "
    kubectl delete pipelinerun/"${pr}" --wait=true 2>/dev/null || true
    kubectl apply -f "${SNAP_DIR}/${pr}.yaml" >/dev/null 2>&1 || true
    sleep 5
    if wait_for_run "${pr}"; then
        echo "PASSED"
    else
        echo "FAILED"
        dump_run "${pr}"
        exit 1
    fi
fi

echo ""
echo "=== E2E tests passed ==="
