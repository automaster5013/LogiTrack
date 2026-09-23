import re
from pathlib import Path

import yaml


WORKFLOW_PATH = Path(".github/workflows/cflite_pr.yml")
PINNED_ACTION = re.compile(r"^google/clusterfuzzlite/actions/(build|run)_fuzzers@[0-9a-f]{40}$")


def main() -> None:
    source = WORKFLOW_PATH.read_text(encoding="utf-8")
    workflow = yaml.safe_load(source)
    if workflow.get("permissions") != {"contents": "read"}:
        raise AssertionError("fuzzing workflow permissions must be contents: read")

    pull_request = workflow.get(True, {}).get("pull_request")
    if not isinstance(pull_request, dict) or "paths" not in pull_request:
        raise AssertionError("fuzzing must run on relevant pull requests")

    job = workflow["jobs"]["fuzz"]
    if job.get("runs-on") != "ubuntu-24.04" or job.get("timeout-minutes") != 15:
        raise AssertionError("fuzzing runner and timeout must be pinned")

    actions = []
    for step in job.get("steps", []):
        action = step.get("uses")
        if action:
            if not PINNED_ACTION.fullmatch(action):
                raise AssertionError(f"mutable or unexpected fuzzing action: {action}")
            actions.append(action)
        inputs = step.get("with", {})
        if inputs.get("language") not in (None, "jvm"):
            raise AssertionError("fuzzing language must be jvm")
        if inputs.get("sanitizer") not in (None, "address"):
            raise AssertionError("JVM fuzzing sanitizer must be address")

    if len(actions) != 2 or not any("build_fuzzers" in action for action in actions) or not any("run_fuzzers" in action for action in actions):
        raise AssertionError("both ClusterFuzzLite build and run actions are required")
    if "mode: code-change" not in source or "fuzz-seconds: 180" not in source:
        raise AssertionError("PR fuzzing mode or bounded duration is missing")

    for required in (
        Path(".clusterfuzzlite/project.yaml"),
        Path(".clusterfuzzlite/Dockerfile"),
        Path(".clusterfuzzlite/build.sh"),
        Path(".clusterfuzzlite/RouteDeviationFuzzer.java"),
    ):
        if not required.is_file():
            raise AssertionError(f"missing ClusterFuzzLite integration file: {required}")

    dockerfile = Path(".clusterfuzzlite/Dockerfile").read_text(encoding="utf-8")
    if not re.search(r"^FROM gcr\.io/oss-fuzz-base/base-builder-jvm@sha256:[0-9a-f]{64}$", dockerfile, re.MULTILINE):
        raise AssertionError("JVM builder image must be digest pinned")

    print("PASS: ClusterFuzzLite JVM PR fuzzing is pinned and bounded")


if __name__ == "__main__":
    main()
