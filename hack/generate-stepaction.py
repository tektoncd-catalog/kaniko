#!/usr/bin/env python3

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

"""Derive a StepAction YAML from the kaniko Task YAML.

The kaniko task has two steps: build-and-push (the core kaniko step) and
write-url (a trivial shell script). The StepAction merges both into a single
step: kaniko builds the image and a small script writes the URL result.

Workspaces become params:
  - source       → source-path
  - dockerconfig → dockerconfig-path (optional, empty string = not provided)

Usage: generate-stepaction.py <task.yaml> <stepaction.yaml>

Requires PyYAML.
"""

import copy
import re
import sys

import yaml


# --- YAML dumper that uses block scalars for multiline strings ---
class StepActionDumper(yaml.SafeDumper):
    pass


def str_representer(dumper, data):
    if "\n" in data:
        return dumper.represent_scalar("tag:yaml.org,2002:str", data, style="|")
    if data == "" or re.match(r"^[\d.]+$", data):
        return dumper.represent_scalar("tag:yaml.org,2002:str", data, style='"')
    if data.lower() in ("true", "false", "yes", "no"):
        return dumper.represent_scalar("tag:yaml.org,2002:str", data, style='"')
    return dumper.represent_scalar("tag:yaml.org,2002:str", data)


StepActionDumper.add_representer(str, str_representer)


# --- Workspace → param mapping ---
WORKSPACE_PARAMS = [
    {
        "name": "source-path",
        "description": "Path to the source code containing the Dockerfile and build context.",
        "type": "string",
    },
    {
        "name": "dockerconfig-path",
        "description": "Path to a directory containing a docker config.json for registry auth. Empty string means no auth.",
        "type": "string",
        "default": "",
    },
]


def transform_description(desc: str) -> str:
    d = desc.replace("This Task", "This StepAction")
    d = d.replace("this Task", "this StepAction")
    return d


def generate(task_file: str, output_file: str) -> None:
    with open(task_file) as f:
        task = yaml.safe_load(f)

    meta = task["metadata"]
    spec = task["spec"]
    build_step = spec["steps"][0]  # build-and-push

    sa = {
        "apiVersion": "tekton.dev/v1beta1",
        "kind": "StepAction",
        "metadata": {
            "name": meta["name"],
            "labels": {
                "app.kubernetes.io/version": meta.get("labels", {}).get(
                    "app.kubernetes.io/version", "0.1"
                ),
            },
            "annotations": {},
        },
        "spec": {},
    }

    # Copy annotations (skip signature).
    for k, v in meta.get("annotations", {}).items():
        if k == "tekton.dev/signature":
            continue
        sa["metadata"]["annotations"][k] = v

    sa["spec"]["description"] = transform_description(spec.get("description", ""))

    # Params: workspace replacements first, then task params (skip BUILDER_IMAGE,
    # it becomes the step image directly).
    sa["spec"]["params"] = [copy.deepcopy(p) for p in WORKSPACE_PARAMS]
    for p in spec.get("params", []):
        p2 = copy.deepcopy(p)
        if "description" in p2 and isinstance(p2["description"], str):
            p2["description"] = p2["description"].replace("this Task", "this StepAction")
        sa["spec"]["params"].append(p2)

    # Image from the build step
    sa["spec"]["image"] = build_step["image"]

    # Env: carry over from build step + add workspace path env vars
    env = copy.deepcopy(build_step.get("env", []))
    env.append({"name": "SOURCE_PATH", "value": "$(params.source-path)"})
    env.append({"name": "DOCKERCONFIG_PATH", "value": "$(params.dockerconfig-path)"})
    env.append({"name": "IMAGE", "value": "$(params.IMAGE)"})
    env.append({"name": "DOCKERFILE", "value": "$(params.DOCKERFILE)"})
    env.append({"name": "CONTEXT", "value": "$(params.CONTEXT)"})
    sa["spec"]["env"] = env

    # Security context
    if "securityContext" in build_step:
        sa["spec"]["securityContext"] = copy.deepcopy(build_step["securityContext"])

    # Results (step results use $(step.results.*))
    sa["spec"]["results"] = []
    for r in spec.get("results", []):
        sa["spec"]["results"].append(copy.deepcopy(r))

    # Combined script: run kaniko executor then write the URL result.
    # In a StepAction we can't use args with $(params.*) substitution the same
    # way, so we use a script with env vars.
    sa["spec"]["script"] = """#!/busybox/sh
set -e

# Set up docker config if provided
if [ -n "${DOCKERCONFIG_PATH}" ]; then
  mkdir -p "${KANIKO_DIR}/.docker"
  cp "${DOCKERCONFIG_PATH}/config.json" "${KANIKO_DIR}/.docker/config.json" 2>/dev/null || true
fi

# Run kaniko executor
/kaniko/executor \\
  --dockerfile="${DOCKERFILE}" \\
  --context="${SOURCE_PATH}/${CONTEXT}" \\
  --destination="${IMAGE}" \\
  --digest-file="$(step.results.IMAGE_DIGEST.path)" \\
  "$@"

# Write image URL result
printf "%s" "${IMAGE}" > "$(step.results.IMAGE_URL.path)"
"""

    # Args passthrough for EXTRA_ARGS
    sa["spec"]["args"] = ["$(params.EXTRA_ARGS[*])"]

    header = f"# Generated from task/{meta['name']}/{meta['name']}.yaml \u2014 do not edit directly.\n"

    with open(output_file, "w") as f:
        f.write(header)
        yaml.dump(
            sa,
            f,
            Dumper=StepActionDumper,
            default_flow_style=False,
            allow_unicode=True,
            sort_keys=False,
        )


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <task.yaml> <stepaction.yaml>", file=sys.stderr)
        sys.exit(1)
    generate(sys.argv[1], sys.argv[2])
