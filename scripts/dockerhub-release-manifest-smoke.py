import argparse
import hashlib
import json
import re
from datetime import datetime
from pathlib import Path


SERVICES = ("api", "analytics", "simulator", "web", "otel-collector")
DIGEST = re.compile(r"^sha256:[0-9a-f]{64}$")
SHA256 = re.compile(r"^[0-9a-f]{64}$")
REVISION = re.compile(r"^[0-9a-f]{40}$")
UTC_TIMESTAMP = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$")
SCANNER_IMAGE = re.compile(r"^ghcr\.io/aquasecurity/trivy@sha256:[0-9a-f]{64}$")
SEMVER = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+$")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("manifest", type=Path)
    parser.add_argument("--evidence-dir", required=True, type=Path)
    parser.add_argument("--verification-dir", required=True, type=Path)
    parser.add_argument("--revision", required=True)
    parser.add_argument("--published-at", required=True)
    parser.add_argument("--repository", required=True)
    parser.add_argument("--run-id", required=True, type=int)
    parser.add_argument("--run-attempt", required=True, type=int)
    parser.add_argument("--workflow-ref", required=True)
    parser.add_argument("--workflow-sha", required=True)
    parser.add_argument("--scanner-image", required=True)
    parser.add_argument("--scanner-version", required=True)
    parser.add_argument("--evidence-artifact-digest", required=True)
    parser.add_argument("--evidence-artifact-url", required=True)
    return parser.parse_args()


def file_hash(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    args = parse_args()
    if not REVISION.fullmatch(args.revision) or not REVISION.fullmatch(args.workflow_sha):
        raise AssertionError("revision values must be full lowercase Git SHAs")
    if not UTC_TIMESTAMP.fullmatch(args.published_at):
        raise AssertionError("publishedAt must be an exact UTC timestamp")
    datetime.strptime(args.published_at, "%Y-%m-%dT%H:%M:%SZ")
    if args.run_id <= 0 or args.run_attempt <= 0:
        raise AssertionError("workflow run identity must be positive")
    if not SCANNER_IMAGE.fullmatch(args.scanner_image) or not SEMVER.fullmatch(args.scanner_version):
        raise AssertionError("scanner provenance is invalid")

    manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
    expected_fields = {
        "schemaVersion", "revision", "publishedAt", "registry", "namespace",
        "sourceRepository", "imagePlatform", "scannerImage", "scannerVersion",
        "blockedVulnerabilitySeverities", "workflowRunId", "workflowRunAttempt",
        "workflowRunUrl", "workflowEvent", "workflowRef", "workflowSha",
        "artifactRetentionDays", "evidenceArtifact", "evidenceArtifactDigest",
        "evidenceArtifactUrl", "images",
    }
    if set(manifest) != expected_fields or manifest["schemaVersion"] != 5:
        raise AssertionError("Docker Hub release manifest schema is invalid")
    expected_url = f"https://github.com/{args.repository}/actions/runs/{args.run_id}"
    expected_ref = f"{args.repository}/.github/workflows/ci.yml@refs/heads/main"
    expected_values = {
        "revision": args.revision,
        "publishedAt": args.published_at,
        "registry": "docker.io",
        "namespace": "automaster5013",
        "sourceRepository": args.repository,
        "imagePlatform": "linux/amd64",
        "scannerImage": args.scanner_image,
        "scannerVersion": args.scanner_version,
        "blockedVulnerabilitySeverities": ["CRITICAL"],
        "workflowRunId": args.run_id,
        "workflowRunAttempt": args.run_attempt,
        "workflowRunUrl": expected_url,
        "workflowEvent": "push",
        "workflowRef": expected_ref,
        "workflowSha": args.workflow_sha,
        "artifactRetentionDays": 30,
        "evidenceArtifact": f"dockerhub-supply-chain-{args.revision}",
        "evidenceArtifactDigest": args.evidence_artifact_digest,
        "evidenceArtifactUrl": args.evidence_artifact_url,
    }
    for field, expected in expected_values.items():
        if manifest[field] != expected:
            raise AssertionError(f"Docker Hub release manifest {field} does not match")
    if args.workflow_ref != expected_ref:
        raise AssertionError("workflow ref must identify main CI")
    if not DIGEST.fullmatch(args.evidence_artifact_digest):
        raise AssertionError("evidence artifact digest must be SHA-256")
    artifact_url = re.compile(
        rf"^https://github\.com/{re.escape(args.repository)}/actions/runs/"
        rf"{args.run_id}/artifacts/[1-9][0-9]*$"
    )
    if not artifact_url.fullmatch(args.evidence_artifact_url):
        raise AssertionError("evidence artifact URL is outside the workflow run")

    images = manifest["images"]
    if not isinstance(images, list) or [image.get("service") for image in images] != list(SERVICES):
        raise AssertionError("manifest must contain all services once in stable order")
    for image in images:
        service = image["service"]
        expected_image_fields = {
            "service", "repository", "tag", "digest", "uri", "sbomFile",
            "sbomSha256", "vulnerabilityReportFile", "vulnerabilityReportSha256",
            "attestationId", "attestationUrl",
            "provenanceVerificationFile", "provenanceVerificationSha256",
        }
        if set(image) != expected_image_fields:
            raise AssertionError(f"image evidence schema is invalid: {service}")
        repository = f"automaster5013/logitrack-{service}"
        digest = image["digest"]
        if image["repository"] != repository or image["tag"] != args.revision or not DIGEST.fullmatch(digest):
            raise AssertionError(f"image identity is invalid: {service}")
        if image["uri"] != f"docker.io/{repository}@{digest}":
            raise AssertionError(f"image URI is not digest-pinned: {service}")
        attestation_id = image["attestationId"]
        if not isinstance(attestation_id, str) or not re.fullmatch(r"[1-9][0-9]*", attestation_id):
            raise AssertionError(f"attestation ID is invalid: {service}")
        expected_attestation_url = (
            f"https://github.com/{args.repository}/attestations/{attestation_id}"
        )
        if image["attestationUrl"] != expected_attestation_url:
            raise AssertionError(f"attestation URL is outside the source repository: {service}")
        verification_file = f"logitrack-{service}.provenance.json"
        verification_hash = image["provenanceVerificationSha256"]
        verification_path = args.verification_dir / verification_file
        if (
            image["provenanceVerificationFile"] != verification_file
            or not SHA256.fullmatch(verification_hash)
            or not verification_path.is_file()
            or file_hash(verification_path) != verification_hash
        ):
            raise AssertionError(f"provenance verification evidence is invalid: {service}")
        verification = json.loads(verification_path.read_text(encoding="utf-8"))
        expected_subject = f"docker.io/{repository}"
        digest_value = digest.removeprefix("sha256:")
        if not isinstance(verification, list) or not verification:
            raise AssertionError(f"provenance verification result is empty: {service}")
        if not any(
            result.get("verificationResult", {}).get("statement", {}).get("predicateType")
            == "https://slsa.dev/provenance/v1"
            and any(
                subject.get("name") == expected_subject
                and subject.get("digest", {}).get("sha256") == digest_value
                for subject in result.get("verificationResult", {}).get("statement", {}).get("subject", [])
            )
            for result in verification
        ):
            raise AssertionError(f"verified provenance subject does not match: {service}")
        for field, suffix in (("sbom", "cdx.json"), ("vulnerabilityReport", "critical.json")):
            filename = f"logitrack-{service}.{suffix}"
            hash_field = f"{field}Sha256"
            file_field = f"{field}File"
            if image[file_field] != filename or not SHA256.fullmatch(image[hash_field]):
                raise AssertionError(f"{field} identity is invalid: {service}")
            path = args.evidence_dir / filename
            if not path.is_file() or file_hash(path) != image[hash_field]:
                raise AssertionError(f"{field} content hash does not match: {service}")
        report = json.loads((args.evidence_dir / image["vulnerabilityReportFile"]).read_text(encoding="utf-8"))
        if report.get("SchemaVersion") != 2 or not isinstance(report.get("Results"), list):
            raise AssertionError(f"vulnerability report schema is invalid: {service}")

    print("PASS: Docker Hub release manifest binds registry digests to verified provenance and supply-chain evidence")


if __name__ == "__main__":
    main()
