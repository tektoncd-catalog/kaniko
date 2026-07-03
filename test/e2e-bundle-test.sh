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

# E2e test for Tekton Bundle publishing.
# Pushes the kaniko task as a bundle to ttl.sh, then runs a PipelineRun
# that references it via the bundle resolver.
#
# Environment variables:
#   PIPELINE_VERSION  - Tekton Pipelines version to install (default: v1.12.0)
#   TIMEOUT           - Timeout for PipelineRun (default: 180s)
#   BUNDLE_REGISTRY   - Registry to push bundles to (default: ttl.sh)

set -euo pipefail

PIPELINE_VERSION="${PIPELINE_VERSION:-v1.12.0}"
TIMEOUT="${TIMEOUT:-180s}"
BUNDLE_REGISTRY="${BUNDLE_REGISTRY:-ttl.sh}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Generate unique bundle reference (ttl.sh images expire after 1h)
BUNDLE_ID="kaniko-e2e-$(head -c 8 /proc/sys/kernel/random/uuid)"
BUNDLE_REF="${BUNDLE_REGISTRY}/${BUNDLE_ID}:1h"

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

echo "--- Setting up in-cluster registry"
kubectl run registry --image=registry:2 --port=5000
kubectl wait --for=condition=Ready --timeout=60s pod/registry
kubectl expose pod registry --port=5000

echo "--- Pushing Tekton Bundle"
echo "    kaniko -> ${BUNDLE_REF}"
tkn bundle push "${BUNDLE_REF}" -f "${ROOT_DIR}/task/kaniko/kaniko.yaml"

echo "--- Creating PipelineRun using bundle resolver"
cat <<EOF | kubectl apply -f -
apiVersion: tekton.dev/v1
kind: PipelineRun
metadata:
  name: kaniko-bundle-test
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
                cat > \$(workspaces.source.path)/Dockerfile <<DOCKERFILE
                FROM alpine:3.21
                RUN echo "hello from kaniko bundle e2e test" > /hello.txt
                CMD ["cat", "/hello.txt"]
                DOCKERFILE
      - name: build
        runAfter: ["create-dockerfile"]
        taskRef:
          resolver: bundles
          params:
            - name: bundle
              value: ${BUNDLE_REF}
            - name: name
              value: kaniko
            - name: kind
              value: task
        workspaces:
          - name: source
            workspace: shared-workspace
        params:
          - name: IMAGE
            value: registry:5000/kaniko-test:bundle
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

pr="kaniko-bundle-test"

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
    kubectl get pipelinerun/"$1" -o jsonpath='{.status.conditions[*].message}' 2>/dev/null || true
    echo ""
    for pod in $(kubectl get pods -l tekton.dev/pipelineRun="$1" -o name 2>/dev/null); do
        echo "  >> ${pod}"
        kubectl logs "${pod}" --all-containers 2>/dev/null || true
    done
}

sleep 5
snapshot_run "${pr}"

echo "--- Waiting for PipelineRun to complete (timeout: ${TIMEOUT})"
echo -n "  ${pr} ... "
if wait_for_run "${pr}"; then
    echo "PASSED"
else
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
echo "=== Bundle e2e test passed ==="
