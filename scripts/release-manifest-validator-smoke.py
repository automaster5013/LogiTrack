import json
import subprocess
import sys
import tempfile
from pathlib import Path


SERVICES = ("api", "analytics", "simulator", "web", "otel-collector")
REVISION = "a" * 40
ACCOUNT_ID = "123456789012"
REGION = "ap-northeast-2"
REGISTRY = f"{ACCOUNT_ID}.dkr.ecr.{REGION}.amazonaws.com"
PREFIX = "logitrack"
DIGEST = "sha256:" + "b" * 64
SBOM_SHA256 = "c" * 64
REPOSITORY = "automaster5013/LogiTrack"
RUN_ID = 123456789
RUN_ATTEMPT = 2


def run_validator(path: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [
            sys.executable,
            "scripts/release-manifest-smoke.py",
            str(path),
            "--revision",
            REVISION,
            "--account-id",
            ACCOUNT_ID,
            "--region",
            REGION,
            "--repository",
            REPOSITORY,
            "--run-id",
            str(RUN_ID),
            "--run-attempt",
            str(RUN_ATTEMPT),
            "--registry",
            REGISTRY,
            "--repository-prefix",
            PREFIX,
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
            "uri": f"{REGISTRY}/{PREFIX}/{service}@{DIGEST}",
            "sbomFile": f"logitrack-{service}.cdx.json",
            "sbomSha256": SBOM_SHA256,
        }
        for service in SERVICES
    ]
    manifest = {
        "schemaVersion": 2,
        "revision": REVISION,
        "awsAccountId": ACCOUNT_ID,
        "awsRegion": REGION,
        "sourceRepository": REPOSITORY,
        "workflowRunId": RUN_ID,
        "workflowRunAttempt": RUN_ATTEMPT,
        "sbomArtifact": f"staging-container-sboms-{REVISION}",
        "images": images,
    }
    with tempfile.TemporaryDirectory() as directory:
        path = Path(directory) / "manifest.json"
        path.write_text(json.dumps(manifest), encoding="utf-8")
        valid = run_validator(path)
        if valid.returncode != 0:
            raise AssertionError(valid.stderr or valid.stdout)

        manifest["images"][0]["digest"] = "sha256:not-a-digest"
        path.write_text(json.dumps(manifest), encoding="utf-8")
        invalid = run_validator(path)
        if invalid.returncode == 0:
            raise AssertionError("validator accepted an invalid image digest")

        manifest["images"][0]["digest"] = DIGEST
        manifest["images"][0]["sbomSha256"] = "not-a-sha256"
        path.write_text(json.dumps(manifest), encoding="utf-8")
        invalid = run_validator(path)
        if invalid.returncode == 0:
            raise AssertionError("validator accepted an invalid SBOM hash")

        manifest["images"][0]["sbomSha256"] = SBOM_SHA256
        manifest["workflowRunAttempt"] = RUN_ATTEMPT + 1
        path.write_text(json.dumps(manifest), encoding="utf-8")
        invalid = run_validator(path)
        if invalid.returncode == 0:
            raise AssertionError("validator accepted mismatched workflow provenance")

    print("PASS: release manifest validator rejects invalid image, SBOM, or workflow provenance")


if __name__ == "__main__":
    main()
