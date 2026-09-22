import hashlib
import json
import subprocess
import sys
import tempfile
from pathlib import Path


SERVICES = ("api", "analytics", "simulator", "web", "otel-collector")
REVISION = "a" * 40
ACCOUNT_ID = "123456789012"
ARTIFACT_RETENTION_DAYS = 30
DEPLOYMENT_ENVIRONMENT = "staging"
IMAGE_PLATFORM = "linux/amd64"
IMAGE_MEDIA_TYPE = "application/vnd.oci.image.manifest.v1+json"
MAX_IMAGE_SIZE_BYTES = 2 * 1024 * 1024 * 1024
MAX_TOTAL_IMAGE_SIZE_BYTES = 5 * 1024 * 1024 * 1024
IMAGE_SIZE_BYTES = 123456789
SCANNER_IMAGE = "ghcr.io/aquasecurity/trivy@sha256:" + "e" * 64
SCANNER_VERSION = "0.74.0"
BLOCKED_VULNERABILITY_SEVERITIES = "CRITICAL"
REGION = "ap-northeast-2"
REGISTRY = f"{ACCOUNT_ID}.dkr.ecr.{REGION}.amazonaws.com"
PREFIX = "logitrack"
DIGEST = "sha256:" + "b" * 64
SBOM_CONTENT = b'{"bomFormat":"CycloneDX"}\n'
SBOM_SHA256 = hashlib.sha256(SBOM_CONTENT).hexdigest()
SBOM_ARTIFACT_DIGEST = "sha256:" + "c" * 64
REPOSITORY = "automaster5013/LogiTrack"
RUN_ID = 123456789
RUN_ATTEMPT = 2
RUN_URL = f"https://github.com/{REPOSITORY}/actions/runs/{RUN_ID}"
SBOM_ARTIFACT_URL = f"{RUN_URL}/artifacts/987654321"
WORKFLOW_SHA = "d" * 40
WORKFLOW_REF = f"{REPOSITORY}/.github/workflows/publish-staging-images.yml@refs/heads/main"
WORKFLOW_ACTOR = "release-operator"
WORKFLOW_TRIGGERING_ACTOR = "rerun-operator"
WORKFLOW_EVENT = "workflow_dispatch"
PUBLISHED_AT = "2026-09-22T03:04:05Z"


def run_validator(path: Path, sbom_dir: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [
            sys.executable,
            "scripts/release-manifest-smoke.py",
            str(path),
            "--revision",
            REVISION,
            "--account-id",
            ACCOUNT_ID,
            "--artifact-retention-days",
            str(ARTIFACT_RETENTION_DAYS),
            "--deployment-environment",
            DEPLOYMENT_ENVIRONMENT,
            "--blocked-vulnerability-severities",
            BLOCKED_VULNERABILITY_SEVERITIES,
            "--image-platform",
            IMAGE_PLATFORM,
            "--max-image-size-bytes",
            str(MAX_IMAGE_SIZE_BYTES),
            "--max-total-image-size-bytes",
            str(MAX_TOTAL_IMAGE_SIZE_BYTES),
            "--region",
            REGION,
            "--repository",
            REPOSITORY,
            "--published-at",
            PUBLISHED_AT,
            "--run-id",
            str(RUN_ID),
            "--run-attempt",
            str(RUN_ATTEMPT),
            "--run-url",
            RUN_URL,
            "--workflow-sha",
            WORKFLOW_SHA,
            "--workflow-actor",
            WORKFLOW_ACTOR,
            "--workflow-event",
            WORKFLOW_EVENT,
            "--workflow-triggering-actor",
            WORKFLOW_TRIGGERING_ACTOR,
            "--workflow-ref",
            WORKFLOW_REF,
            "--registry",
            REGISTRY,
            "--repository-prefix",
            PREFIX,
            "--sbom-artifact-digest",
            SBOM_ARTIFACT_DIGEST,
            "--sbom-artifact-url",
            SBOM_ARTIFACT_URL,
            "--scanner-image",
            SCANNER_IMAGE,
            "--scanner-version",
            SCANNER_VERSION,
            "--sbom-dir",
            str(sbom_dir),
        ],
        capture_output=True,
        check=False,
        text=True,
    )


def main() -> None:
    images = [
        {
            "service": service,
            "repository": f"{PREFIX}/{service}",
            "digest": DIGEST,
            "mediaType": IMAGE_MEDIA_TYPE,
            "sizeBytes": IMAGE_SIZE_BYTES,
            "uri": f"{REGISTRY}/{PREFIX}/{service}@{DIGEST}",
            "sbomFile": f"logitrack-{service}.cdx.json",
            "sbomSha256": SBOM_SHA256,
        }
        for service in SERVICES
    ]
    manifest = {
        "schemaVersion": 19,
        "revision": REVISION,
        "publishedAt": PUBLISHED_AT,
        "deploymentEnvironment": DEPLOYMENT_ENVIRONMENT,
        "imagePlatform": IMAGE_PLATFORM,
        "maxImageSizeBytes": MAX_IMAGE_SIZE_BYTES,
        "maxTotalImageSizeBytes": MAX_TOTAL_IMAGE_SIZE_BYTES,
        "totalImageSizeBytes": IMAGE_SIZE_BYTES * len(SERVICES),
        "scannerImage": SCANNER_IMAGE,
        "scannerVersion": SCANNER_VERSION,
        "blockedVulnerabilitySeverities": [BLOCKED_VULNERABILITY_SEVERITIES],
        "awsAccountId": ACCOUNT_ID,
        "awsRegion": REGION,
        "sourceRepository": REPOSITORY,
        "workflowRunId": RUN_ID,
        "workflowRunAttempt": RUN_ATTEMPT,
        "workflowRunUrl": RUN_URL,
        "workflowActor": WORKFLOW_ACTOR,
        "workflowTriggeringActor": WORKFLOW_TRIGGERING_ACTOR,
        "workflowEvent": WORKFLOW_EVENT,
        "workflowRef": WORKFLOW_REF,
        "workflowSha": WORKFLOW_SHA,
        "artifactRetentionDays": ARTIFACT_RETENTION_DAYS,
        "sbomArtifact": f"staging-container-sboms-{REVISION}",
        "sbomArtifactDigest": SBOM_ARTIFACT_DIGEST,
        "sbomArtifactUrl": SBOM_ARTIFACT_URL,
        "images": images,
    }
    with tempfile.TemporaryDirectory() as directory:
        temp_dir = Path(directory)
        path = temp_dir / "manifest.json"
        sbom_dir = temp_dir / "sbom"
        sbom_dir.mkdir()
        for service in SERVICES:
            (sbom_dir / f"logitrack-{service}.cdx.json").write_bytes(SBOM_CONTENT)
        path.write_text(json.dumps(manifest), encoding="utf-8")
        valid = run_validator(path, sbom_dir)
        if valid.returncode != 0:
            raise AssertionError(valid.stderr or valid.stdout)

        manifest["images"][0]["digest"] = "sha256:not-a-digest"
        path.write_text(json.dumps(manifest), encoding="utf-8")
        invalid = run_validator(path, sbom_dir)
        if invalid.returncode == 0:
            raise AssertionError("validator accepted an invalid image digest")

        manifest["images"][0]["digest"] = DIGEST
        manifest["images"][0]["mediaType"] = "application/vnd.oci.image.index.v1+json"
        path.write_text(json.dumps(manifest), encoding="utf-8")
        invalid = run_validator(path, sbom_dir)
        if invalid.returncode == 0:
            raise AssertionError("validator accepted an image index media type")

        manifest["images"][0]["mediaType"] = IMAGE_MEDIA_TYPE
        manifest["images"][0]["sizeBytes"] = MAX_IMAGE_SIZE_BYTES + 1
        path.write_text(json.dumps(manifest), encoding="utf-8")
        invalid = run_validator(path, sbom_dir)
        if invalid.returncode == 0:
            raise AssertionError("validator accepted an oversized image")

        manifest["images"][0]["sizeBytes"] = IMAGE_SIZE_BYTES
        manifest["images"][0]["sbomSha256"] = "not-a-sha256"
        path.write_text(json.dumps(manifest), encoding="utf-8")
        invalid = run_validator(path, sbom_dir)
        if invalid.returncode == 0:
            raise AssertionError("validator accepted an invalid SBOM hash")

        manifest["images"][0]["sbomSha256"] = SBOM_SHA256
        api_sbom = sbom_dir / "logitrack-api.cdx.json"
        api_sbom.write_bytes(b"tampered")
        path.write_text(json.dumps(manifest), encoding="utf-8")
        invalid = run_validator(path, sbom_dir)
        if invalid.returncode == 0:
            raise AssertionError("validator accepted tampered SBOM contents")

        api_sbom.write_bytes(SBOM_CONTENT)
        manifest["sbomArtifactDigest"] = "sha256:" + "d" * 64
        path.write_text(json.dumps(manifest), encoding="utf-8")
        invalid = run_validator(path, sbom_dir)
        if invalid.returncode == 0:
            raise AssertionError("validator accepted mismatched SBOM artifact digest")

        manifest["sbomArtifactDigest"] = SBOM_ARTIFACT_DIGEST
        manifest["sbomArtifactUrl"] = SBOM_ARTIFACT_URL.replace(
            f"runs/{RUN_ID}", f"runs/{RUN_ID + 1}"
        )
        path.write_text(json.dumps(manifest), encoding="utf-8")
        invalid = run_validator(path, sbom_dir)
        if invalid.returncode == 0:
            raise AssertionError("validator accepted an SBOM artifact URL from another run")

        manifest["sbomArtifactUrl"] = SBOM_ARTIFACT_URL
        manifest["workflowRunUrl"] = RUN_URL + "/unexpected"
        path.write_text(json.dumps(manifest), encoding="utf-8")
        invalid = run_validator(path, sbom_dir)
        if invalid.returncode == 0:
            raise AssertionError("validator accepted a mismatched workflow run URL")

        manifest["workflowRunUrl"] = RUN_URL
        manifest["workflowRunAttempt"] = RUN_ATTEMPT + 1
        path.write_text(json.dumps(manifest), encoding="utf-8")
        invalid = run_validator(path, sbom_dir)
        if invalid.returncode == 0:
            raise AssertionError("validator accepted mismatched workflow provenance")

        manifest["workflowRunAttempt"] = RUN_ATTEMPT
        manifest["workflowSha"] = "not-a-sha"
        path.write_text(json.dumps(manifest), encoding="utf-8")
        invalid = run_validator(path, sbom_dir)
        if invalid.returncode == 0:
            raise AssertionError("validator accepted an invalid workflow definition SHA")

        manifest["workflowSha"] = WORKFLOW_SHA
        manifest["workflowRef"] = WORKFLOW_REF.replace("refs/heads/main", "refs/heads/feature")
        path.write_text(json.dumps(manifest), encoding="utf-8")
        invalid = run_validator(path, sbom_dir)
        if invalid.returncode == 0:
            raise AssertionError("validator accepted a non-main workflow definition ref")

        manifest["workflowRef"] = WORKFLOW_REF
        manifest["workflowActor"] = "invalid_actor"
        path.write_text(json.dumps(manifest), encoding="utf-8")
        invalid = run_validator(path, sbom_dir)
        if invalid.returncode == 0:
            raise AssertionError("validator accepted an invalid workflow actor")

        manifest["workflowActor"] = WORKFLOW_ACTOR
        manifest["workflowTriggeringActor"] = "-invalid"
        path.write_text(json.dumps(manifest), encoding="utf-8")
        invalid = run_validator(path, sbom_dir)
        if invalid.returncode == 0:
            raise AssertionError("validator accepted an invalid triggering actor")

        manifest["workflowTriggeringActor"] = WORKFLOW_TRIGGERING_ACTOR
        manifest["workflowEvent"] = "push"
        path.write_text(json.dumps(manifest), encoding="utf-8")
        invalid = run_validator(path, sbom_dir)
        if invalid.returncode == 0:
            raise AssertionError("validator accepted a non-manual workflow event")

        manifest["workflowEvent"] = WORKFLOW_EVENT
        manifest["deploymentEnvironment"] = "production"
        path.write_text(json.dumps(manifest), encoding="utf-8")
        invalid = run_validator(path, sbom_dir)
        if invalid.returncode == 0:
            raise AssertionError("validator accepted a non-staging deployment environment")

        manifest["deploymentEnvironment"] = DEPLOYMENT_ENVIRONMENT
        manifest["imagePlatform"] = "linux/arm64"
        path.write_text(json.dumps(manifest), encoding="utf-8")
        invalid = run_validator(path, sbom_dir)
        if invalid.returncode == 0:
            raise AssertionError("validator accepted an unsupported image platform")

        manifest["imagePlatform"] = IMAGE_PLATFORM
        manifest["maxImageSizeBytes"] = MAX_IMAGE_SIZE_BYTES // 2
        path.write_text(json.dumps(manifest), encoding="utf-8")
        invalid = run_validator(path, sbom_dir)
        if invalid.returncode == 0:
            raise AssertionError("validator accepted a mismatched image size policy")

        manifest["maxImageSizeBytes"] = MAX_IMAGE_SIZE_BYTES
        manifest["maxTotalImageSizeBytes"] = MAX_TOTAL_IMAGE_SIZE_BYTES // 2
        path.write_text(json.dumps(manifest), encoding="utf-8")
        invalid = run_validator(path, sbom_dir)
        if invalid.returncode == 0:
            raise AssertionError("validator accepted a mismatched total image size policy")

        manifest["maxTotalImageSizeBytes"] = MAX_TOTAL_IMAGE_SIZE_BYTES
        manifest["totalImageSizeBytes"] += 1
        path.write_text(json.dumps(manifest), encoding="utf-8")
        invalid = run_validator(path, sbom_dir)
        if invalid.returncode == 0:
            raise AssertionError("validator accepted an incorrect total image size")

        manifest["totalImageSizeBytes"] = IMAGE_SIZE_BYTES * len(SERVICES)
        manifest["scannerImage"] = "ghcr.io/aquasecurity/trivy:latest"
        path.write_text(json.dumps(manifest), encoding="utf-8")
        invalid = run_validator(path, sbom_dir)
        if invalid.returncode == 0:
            raise AssertionError("validator accepted a tag-based scanner image")

        manifest["scannerImage"] = SCANNER_IMAGE
        manifest["scannerVersion"] = "v0.74"
        path.write_text(json.dumps(manifest), encoding="utf-8")
        invalid = run_validator(path, sbom_dir)
        if invalid.returncode == 0:
            raise AssertionError("validator accepted an invalid scanner version")

        manifest["scannerVersion"] = SCANNER_VERSION
        manifest["blockedVulnerabilitySeverities"] = ["HIGH", "CRITICAL"]
        path.write_text(json.dumps(manifest), encoding="utf-8")
        invalid = run_validator(path, sbom_dir)
        if invalid.returncode == 0:
            raise AssertionError("validator accepted a mismatched vulnerability policy")

        manifest["blockedVulnerabilitySeverities"] = [BLOCKED_VULNERABILITY_SEVERITIES]
        manifest["publishedAt"] = "2026-99-99T03:04:05Z"
        path.write_text(json.dumps(manifest), encoding="utf-8")
        invalid = run_validator(path, sbom_dir)
        if invalid.returncode == 0:
            raise AssertionError("validator accepted an invalid publication timestamp")

        manifest["publishedAt"] = PUBLISHED_AT
        manifest["artifactRetentionDays"] = ARTIFACT_RETENTION_DAYS + 1
        path.write_text(json.dumps(manifest), encoding="utf-8")
        invalid = run_validator(path, sbom_dir)
        if invalid.returncode == 0:
            raise AssertionError("validator accepted mismatched artifact retention")

    print("PASS: release manifest validator rejects invalid image, SBOM contents, or workflow provenance")


if __name__ == "__main__":
    main()
