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

# Release script for tektoncd-catalog/kaniko.
#
# Usage:
#   ./hack/release.sh v0.2.0              # bump, regenerate, commit, tag, push
#   ./hack/release.sh v0.2.0 --dry-run    # show what would change

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

VERSION=""
DRY_RUN=false

for arg in "$@"; do
    case "${arg}" in
        --dry-run) DRY_RUN=true ;;
        v*) VERSION="${arg}" ;;
        *) echo "Unknown argument: ${arg}"; exit 1 ;;
    esac
done

if [[ -z "${VERSION}" ]]; then
    echo "Usage: $0 <version> [--dry-run]"
    echo "  Example: $0 v0.2.0"
    exit 1
fi

if ! echo "${VERSION}" | grep -qE '^v[0-9]+\.[0-9]+\.[0-9]+$'; then
    echo "Error: version must match vX.Y.Z (got: ${VERSION})"
    exit 1
fi

BARE_VERSION="${VERSION#v}"

cd "${ROOT_DIR}"

# Detect current version from the Task
CURRENT_VERSION=$(yq '.metadata.labels["app.kubernetes.io/version"]' task/kaniko/kaniko.yaml)

echo "=== Release ${VERSION} ==="
echo "  Current: ${CURRENT_VERSION}"
echo "  Target:  ${BARE_VERSION}"
echo ""

# Ensure we're on main and up to date
BRANCH=$(git branch --show-current)
if [[ "${DRY_RUN}" != true ]]; then
    if [[ "${BRANCH}" != "main" ]]; then
        echo "Error: must be on main branch (currently on: ${BRANCH})"
        exit 1
    fi
    git fetch origin main
    LOCAL=$(git rev-parse HEAD)
    REMOTE=$(git rev-parse origin/main)
    if [[ "${LOCAL}" != "${REMOTE}" ]]; then
        echo "Error: local main is not up to date with origin/main"
        exit 1
    fi
else
    git fetch origin main 2>/dev/null || true
fi

echo "--- Bumping version in Task"
yq -i ".metadata.labels[\"app.kubernetes.io/version\"] = \"${BARE_VERSION}\"" task/kaniko/kaniko.yaml

echo "--- Regenerating StepAction"
"${SCRIPT_DIR}/generate-stepaction.sh"

echo "--- Files changed:"
git --no-pager diff --stat

if [[ "${DRY_RUN}" == true ]]; then
    echo ""
    echo "--- Dry run: showing changes ---"
    git --no-pager diff -- task/ stepaction/
    echo ""
    echo "--- Restoring working tree (dry run) ---"
    git checkout -- task/ stepaction/ 2>/dev/null || true
    echo "Dry run complete. Run without --dry-run to apply."
    exit 0
fi

# Generate changelog from commits
COMMITS=$(git log --oneline "v${CURRENT_VERSION}..HEAD" --no-merges 2>/dev/null || git log --oneline -10)
TAG_MESSAGE="Release ${VERSION}

Changes since v${CURRENT_VERSION}:
$(echo "${COMMITS}" | sed 's/^[a-f0-9]* /- /')"

echo "--- Committing..."
git add task/ stepaction/
git commit --signoff --message "chore: bump version to ${VERSION}"

echo "--- Pushing to main..."
git push origin main:main

echo "--- Tagging ${VERSION}..."
git tag -a "${VERSION}" -m "${TAG_MESSAGE}"

echo "--- Pushing tag..."
git push origin "refs/tags/${VERSION}:refs/tags/${VERSION}"

echo ""
echo "=== Release ${VERSION} initiated ==="
echo "  Monitor: gh run list --workflow=release.yaml --limit 1"
echo "  View:    https://github.com/tektoncd-catalog/kaniko/releases/tag/${VERSION}"
