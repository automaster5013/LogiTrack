import re
from pathlib import Path

import yaml


WORKFLOW_PATH = Path(".github/workflows/ci.yml")
PINNED_ACTION = re.compile(r"^[^@\s]+@[0-9a-f]{40}$")


def main() -> None:
    source = WORKFLOW_PATH.read_text(encoding="utf-8")
    workflow = yaml.safe_load(source)
    jobs = workflow.get("jobs", {})
    if not jobs:
        raise AssertionError("CI workflow has no jobs")

    for job_name, job in jobs.items():
        if job_name == "dockerhub":
            if job.get("uses") != "./.github/workflows/publish-dockerhub-images.yml":
                raise AssertionError("Docker Hub job must call the repository reusable workflow")
            if job.get("needs") != "containers":
                raise AssertionError("Docker Hub publication must wait for container CI")
            if str(job.get("if", "")) != "github.event_name == 'push' && github.ref == 'refs/heads/main'":
                raise AssertionError("Docker Hub publication must only run for main pushes")
            if job.get("secrets") != {"DOCKERHUB_TOKEN": "${{ secrets.DOCKERHUB_TOKEN }}"}:
                raise AssertionError("Docker Hub publication must receive only its dedicated secret")
            continue
        if job.get("runs-on") != "ubuntu-24.04":
            raise AssertionError(f"{job_name} runner OS is not pinned to ubuntu-24.04")
        timeout = job.get("timeout-minutes")
        if not isinstance(timeout, int) or timeout <= 0:
            raise AssertionError(f"{job_name} does not have a positive timeout")
        for step in job.get("steps", []):
            action = step.get("uses")
            if action and not PINNED_ACTION.fullmatch(action):
                raise AssertionError(f"{job_name} uses a mutable action reference: {action}")

    if workflow.get("permissions") != {"contents": "read"}:
        raise AssertionError("CI workflow permissions are broader than contents: read")
    if "ubuntu-latest" in source:
        raise AssertionError("CI workflow still relies on the moving ubuntu-latest label")

    print("PASS: CI runners, action sources, timeouts, and token permissions are bounded")


if __name__ == "__main__":
    main()
