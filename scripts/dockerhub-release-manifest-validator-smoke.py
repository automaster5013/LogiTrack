import hashlib
import json
import subprocess
import sys
import tempfile
from pathlib import Path


SERVICES = ("api", "analytics", "simulator", "web", "otel-collector")
REVISION = "a" * 40
DIGEST = "sha256:" + "b" * 64
REPOSITORY = "automaster5013/LogiTrack"
RUN_ID = 123456
RUN_ATTEMPT = 2
PUBLISHED_AT = "2026-09-26T01:02:03Z"
WORKFLOW_SHA = "c" * 40
WORKFLOW_REF = f"{REPOSITORY}/.github/workflows/ci.yml@refs/heads/main"
SCANNER_IMAGE = "ghcr.io/aquasecurity/trivy@sha256:" + "d" * 64
SCANNER_VERSION = "0.74.0"
EVIDENCE_ARTIFACT_DIGEST = "sha256:" + "e" * 64
EVIDENCE_ARTIFACT_URL = f"https://github.com/{REPOSITORY}/actions/runs/{RUN_ID}/artifacts/987654"
SBOM = b'{"bomFormat":"CycloneDX"}\n'
REPORT = b'{"SchemaVersion":2,"Results":[]}\n'


def run(path: Path, evidence: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run([
        sys.executable, "scripts/dockerhub-release-manifest-smoke.py", str(path),
        "--evidence-dir", str(evidence), "--revision", REVISION,
        "--published-at", PUBLISHED_AT, "--repository", REPOSITORY,
        "--run-id", str(RUN_ID), "--run-attempt", str(RUN_ATTEMPT),
        "--workflow-ref", WORKFLOW_REF, "--workflow-sha", WORKFLOW_SHA,
        "--scanner-image", SCANNER_IMAGE, "--scanner-version", SCANNER_VERSION,
        "--evidence-artifact-digest", EVIDENCE_ARTIFACT_DIGEST,
        "--evidence-artifact-url", EVIDENCE_ARTIFACT_URL,
    ], capture_output=True, text=True, check=False)


def main() -> None:
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        images = []
        for service in SERVICES:
            sbom_file = f"logitrack-{service}.cdx.json"
            report_file = f"logitrack-{service}.critical.json"
            (root / sbom_file).write_bytes(SBOM)
            (root / report_file).write_bytes(REPORT)
            images.append({
                "service": service, "repository": f"automaster5013/logitrack-{service}",
                "tag": REVISION, "digest": DIGEST,
                "uri": f"docker.io/automaster5013/logitrack-{service}@{DIGEST}",
                "sbomFile": sbom_file, "sbomSha256": hashlib.sha256(SBOM).hexdigest(),
                "vulnerabilityReportFile": report_file,
                "vulnerabilityReportSha256": hashlib.sha256(REPORT).hexdigest(),
            })
        manifest = {
            "schemaVersion": 3, "revision": REVISION, "publishedAt": PUBLISHED_AT,
            "registry": "docker.io", "namespace": "automaster5013",
            "sourceRepository": REPOSITORY, "imagePlatform": "linux/amd64",
            "scannerImage": SCANNER_IMAGE, "scannerVersion": SCANNER_VERSION,
            "blockedVulnerabilitySeverities": ["CRITICAL"], "workflowRunId": RUN_ID,
            "workflowRunAttempt": RUN_ATTEMPT,
            "workflowRunUrl": f"https://github.com/{REPOSITORY}/actions/runs/{RUN_ID}",
            "workflowEvent": "push", "workflowRef": WORKFLOW_REF,
            "workflowSha": WORKFLOW_SHA, "artifactRetentionDays": 30, "images": images,
            "evidenceArtifact": f"dockerhub-supply-chain-{REVISION}",
            "evidenceArtifactDigest": EVIDENCE_ARTIFACT_DIGEST,
            "evidenceArtifactUrl": EVIDENCE_ARTIFACT_URL,
        }
        path = root / "manifest.json"
        path.write_text(json.dumps(manifest), encoding="utf-8")
        if run(path, root).returncode != 0:
            raise AssertionError("validator rejected valid Docker Hub evidence")
        manifest["images"][0]["sbomSha256"] = "0" * 64
        path.write_text(json.dumps(manifest), encoding="utf-8")
        if run(path, root).returncode == 0:
            raise AssertionError("validator accepted a mismatched SBOM hash")
        manifest["images"][0]["sbomSha256"] = hashlib.sha256(SBOM).hexdigest()
        manifest["workflowRunUrl"] += "/wrong"
        path.write_text(json.dumps(manifest), encoding="utf-8")
        if run(path, root).returncode == 0:
            raise AssertionError("validator accepted mismatched workflow provenance")
        manifest["workflowRunUrl"] = f"https://github.com/{REPOSITORY}/actions/runs/{RUN_ID}"
        manifest["evidenceArtifactUrl"] = EVIDENCE_ARTIFACT_URL.replace(
            f"runs/{RUN_ID}", f"runs/{RUN_ID + 1}"
        )
        path.write_text(json.dumps(manifest), encoding="utf-8")
        if run(path, root).returncode == 0:
            raise AssertionError("validator accepted evidence from a different workflow run")
    print("PASS: Docker Hub release manifest validator rejects altered evidence and provenance")


if __name__ == "__main__":
    main()
