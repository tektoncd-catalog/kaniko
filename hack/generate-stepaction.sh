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

# Generate the StepAction from the Task.
# Usage: ./hack/generate-stepaction.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

TASK_FILE="${ROOT_DIR}/task/kaniko/kaniko.yaml"
SA_FILE="${ROOT_DIR}/stepaction/kaniko/kaniko.yaml"

mkdir -p "$(dirname "${SA_FILE}")"

# Python runner: prefer uv (pulls in PyYAML), fall back to python3 with yaml.
if command -v uv &>/dev/null; then
  PYRUN=(uv run --quiet --with pyyaml python3)
elif python3 -c 'import yaml' 2>/dev/null; then
  PYRUN=(python3)
else
  echo "Error: need either 'uv' or a python3 with PyYAML" >&2
  exit 1
fi

"${PYRUN[@]}" "${SCRIPT_DIR}/generate-stepaction.py" "${TASK_FILE}" "${SA_FILE}"
echo "Generated ${SA_FILE}"
