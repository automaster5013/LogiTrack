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
        }
        for service in SERVICES
    ]
    manifest = {
        "schemaVersion": 1,
        "revision": REVISION,
        "awsAccountId": ACCOUNT_ID,
        "awsRegion": REGION,
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

    print("PASS: release manifest validator accepts pinned images and rejects invalid digests")


if __name__ == "__main__":
    main()
