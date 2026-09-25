import re
from pathlib import Path

import yaml


WORKFLOW_PATH = Path(".github/workflows/publish-dockerhub-images.yml")
PINNED_ACTION = re.compile(r"^[^@\s]+@[0-9a-f]{40}$")
SERVICES = ("api", "analytics", "simulator", "web", "otel-collector")


def main() -> None:
    source = WORKFLOW_PATH.read_text(encoding="utf-8")
    workflow = yaml.safe_load(source)
    job = workflow.get("jobs", {}).get("publish", {})

    if not re.search(r"(?m)^on:\s*\n\s+workflow_call:\s*$", source):
        raise AssertionError("Docker Hub publication must only be a reusable workflow")
    if workflow.get("permissions") != {"contents": "read"}:
        raise AssertionError("Docker Hub publication permissions must be read-only")
    if workflow.get("concurrency", {}).get("cancel-in-progress") is not False:
        raise AssertionError("an in-flight immutable publication must not be cancelled")
    if job.get("runs-on") != "ubuntu-24.04" or job.get("timeout-minutes") != 45:
        raise AssertionError("Docker Hub publication runner and timeout are not bounded")

    for step in job.get("steps", []):
        action = step.get("uses")
        if action and not PINNED_ACTION.fullmatch(action):
            raise AssertionError(f"Docker Hub publication uses a mutable action reference: {action}")

    required = (
        "workflow_call:",
        "DOCKERHUB_TOKEN:\n        required: true",
        "DOCKERHUB_NAMESPACE: automaster5013",
        "secrets.DOCKERHUB_TOKEN",
        "git merge-base --is-ancestor",
        "org.opencontainers.image.source",
        "org.opencontainers.image.revision",
        "linux/amd64",
        "scripts/sbom-smoke.py",
        "--severity CRITICAL",
        "Push immutable images and verify registry digests",
        "docker buildx imagetools inspect",
        "already exists with different immutable content",
        "remote_image_id",
        "local_image_id",
        "docker pull --platform",
        "release-manifest.json",
        "dockerhub-release-manifest-smoke.py",
        "workflowRunAttempt",
        "workflowRunUrl",
        "workflowRef",
        "workflowSha",
        "sbomSha256",
        "vulnerabilityReportSha256",
        "evidenceArtifactDigest",
        "evidenceArtifactUrl",
        "dockerhub-supply-chain-${{ github.sha }}",
        "Upload immutable Docker Hub release manifest",
        "published-at=$published_at",
        "dockerhub-release-${{ github.sha }}",
        "TRIGGER_REF: ${{ github.ref }}",
        "test \"$TRIGGER_REF\" = refs/heads/main",
    )
    for value in required:
        if value not in source:
            raise AssertionError(f"Docker Hub publication lacks required control: {value}")
    if ":latest" in source:
        raise AssertionError("Docker Hub publication must not create mutable latest tags")
    for service in SERVICES:
        if f"logitrack-{service}:$REVISION" not in source:
            raise AssertionError(f"Docker Hub publication does not build {service} by commit SHA")

    scan_index = source.index("Generate and validate supply-chain evidence")
    push_index = source.index("Push immutable images and verify registry digests")
    evidence_upload_index = source.index("Upload immutable Docker Hub supply-chain evidence")
    upload_index = source.index("Upload immutable Docker Hub release manifest")
    if not scan_index < evidence_upload_index < push_index < upload_index:
        raise AssertionError("evidence must be uploaded before digest-bound publication manifest")
    if source.count("retention-days: ${{ env.ARTIFACT_RETENTION_DAYS }}") != 2:
        raise AssertionError("both Docker Hub evidence artifacts must share the retention policy")

    ci_source = Path(".github/workflows/ci.yml").read_text(encoding="utf-8")
    for value in (
        "needs: containers",
        "if: github.event_name == 'push' && github.ref == 'refs/heads/main'",
        "uses: ./.github/workflows/publish-dockerhub-images.yml",
        "DOCKERHUB_TOKEN: ${{ secrets.DOCKERHUB_TOKEN }}",
    ):
        if value not in ci_source:
            raise AssertionError(f"CI does not safely gate the reusable Docker Hub workflow: {value}")

    print("PASS: Docker Hub CD is CI-gated, least-privileged, scanned, immutable, and digest-verified")


if __name__ == "__main__":
    main()
