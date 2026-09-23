import re
from pathlib import Path

import yaml


WORKFLOW_PATH = Path(".github/workflows/dependency-review.yml")
PINNED_ACTION = re.compile(r"^[^@\s]+@[0-9a-f]{40}$")


def main() -> None:
    source = WORKFLOW_PATH.read_text(encoding="utf-8")
    workflow = yaml.safe_load(source)
    review = workflow["jobs"]["review"]

    if "pull_request:" not in source or "pull_request_target" in source:
        raise AssertionError("Dependency review must run in the unprivileged pull_request context")
    if workflow.get("permissions") != {"contents": "read"}:
        raise AssertionError("Dependency review token permissions exceed contents: read")
    if review.get("runs-on") != "ubuntu-24.04" or review.get("timeout-minutes") != 5:
        raise AssertionError("Dependency review runner or timeout is not bounded")
    if review.get("name") != "Dependency vulnerability review":
        raise AssertionError("Dependency review required-check name drifted")

    steps = review.get("steps", [])
    if len(steps) != 1 or not PINNED_ACTION.fullmatch(steps[0].get("uses", "")):
        raise AssertionError("Dependency review must use exactly one SHA-pinned action")
    expected = {
        "fail-on-severity": "moderate",
        "retry-on-snapshot-warnings": True,
        "retry-on-snapshot-warnings-timeout": 120,
    }
    if steps[0].get("with") != expected:
        raise AssertionError("Dependency review vulnerability or snapshot retry policy drifted")

    print("PASS: dependency review context, permissions, action pin, severity, and retries are bounded")


if __name__ == "__main__":
    main()
