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


def run(path: Path, evidence: Path, verification: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run([
        sys.executable, "scripts/dockerhub-release-manifest-smoke.py", str(path),
        "--evidence-dir", str(evidence), "--revision", REVISION,
        "--verification-dir", str(verification),
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
        verification_root = root / "verification"
        verification_root.mkdir()
        for index, service in enumerate(SERVICES, start=1):
            sbom_file = f"logitrack-{service}.cdx.json"
            report_file = f"logitrack-{service}.critical.json"
            (root / sbom_file).write_bytes(SBOM)
            (root / report_file).write_bytes(REPORT)
            verification_file = f"logitrack-{service}.provenance.json"
            verification = json.dumps([{"attestation": {}, "verificationResult": {"statement": {
                "predicateType": "https://slsa.dev/provenance/v1",
                "subject": [{"name": f"docker.io/automaster5013/logitrack-{service}",
                             "digest": {"sha256": DIGEST.removeprefix("sha256:")}}],
            }}}], separators=(",", ":")).encode()
            (verification_root / verification_file).write_bytes(verification)
            images.append({
                "service": service, "repository": f"automaster5013/logitrack-{service}",
                "tag": REVISION, "digest": DIGEST,
                "uri": f"docker.io/automaster5013/logitrack-{service}@{DIGEST}",
                "sbomFile": sbom_file, "sbomSha256": hashlib.sha256(SBOM).hexdigest(),
                "vulnerabilityReportFile": report_file,
                "vulnerabilityReportSha256": hashlib.sha256(REPORT).hexdigest(),
                "attestationId": str(700000 + index),
                "attestationUrl": f"https://github.com/{REPOSITORY}/attestations/{700000 + index}",
                "provenanceVerificationFile": verification_file,
                "provenanceVerificationSha256": hashlib.sha256(verification).hexdigest(),
            })
        manifest = {
            "schemaVersion": 5, "revision": REVISION, "publishedAt": PUBLISHED_AT,
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
        if run(path, root, verification_root).returncode != 0:
            raise AssertionError("validator rejected valid Docker Hub evidence")
        manifest["images"][0]["sbomSha256"] = "0" * 64
        path.write_text(json.dumps(manifest), encoding="utf-8")
        if run(path, root, verification_root).returncode == 0:
            raise AssertionError("validator accepted a mismatched SBOM hash")
        manifest["images"][0]["sbomSha256"] = hashlib.sha256(SBOM).hexdigest()
        manifest["workflowRunUrl"] += "/wrong"
        path.write_text(json.dumps(manifest), encoding="utf-8")
        if run(path, root, verification_root).returncode == 0:
            raise AssertionError("validator accepted mismatched workflow provenance")
        manifest["workflowRunUrl"] = f"https://github.com/{REPOSITORY}/actions/runs/{RUN_ID}"
        manifest["evidenceArtifactUrl"] = EVIDENCE_ARTIFACT_URL.replace(
            f"runs/{RUN_ID}", f"runs/{RUN_ID + 1}"
        )
        path.write_text(json.dumps(manifest), encoding="utf-8")
        if run(path, root, verification_root).returncode == 0:
            raise AssertionError("validator accepted evidence from a different workflow run")
        manifest["evidenceArtifactUrl"] = EVIDENCE_ARTIFACT_URL
        manifest["images"][0]["attestationUrl"] = (
            f"https://github.com/another/repository/attestations/700001"
        )
        path.write_text(json.dumps(manifest), encoding="utf-8")
        if run(path, root, verification_root).returncode == 0:
            raise AssertionError("validator accepted an attestation from another repository")
        manifest["images"][0]["attestationUrl"] = (
            f"https://github.com/{REPOSITORY}/attestations/700001"
        )
        manifest["images"][0]["provenanceVerificationSha256"] = "0" * 64
        path.write_text(json.dumps(manifest), encoding="utf-8")
        if run(path, root, verification_root).returncode == 0:
            raise AssertionError("validator accepted altered provenance verification evidence")
        first_verification = verification_root / "logitrack-api.provenance.json"
        altered = json.loads(first_verification.read_text(encoding="utf-8"))
        altered[0]["verificationResult"]["statement"]["subject"][0]["name"] = (
            "docker.io/automaster5013/logitrack-analytics"
        )
        altered_bytes = json.dumps(altered, separators=(",", ":")).encode()
        first_verification.write_bytes(altered_bytes)
        manifest["images"][0]["provenanceVerificationSha256"] = hashlib.sha256(
            altered_bytes
        ).hexdigest()
        path.write_text(json.dumps(manifest), encoding="utf-8")
        if run(path, root, verification_root).returncode == 0:
            raise AssertionError("validator accepted provenance for a different image")
    print("PASS: Docker Hub release manifest validator rejects altered evidence and provenance")


if __name__ == "__main__":
    main()
