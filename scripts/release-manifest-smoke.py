import argparse
import hashlib
import json
import re
from pathlib import Path


SERVICES = ("api", "analytics", "simulator", "web", "otel-collector")
DIGEST = re.compile(r"^sha256:[0-9a-f]{64}$")
SHA256 = re.compile(r"^[0-9a-f]{64}$")
REVISION = re.compile(r"^[0-9a-f]{40}$")
ACCOUNT_ID = re.compile(r"^[0-9]{12}$")
REGION = re.compile(r"^[a-z]{2}(-gov)?-[a-z]+-[0-9]+$")
REPOSITORY = re.compile(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")
GITHUB_LOGIN = re.compile(r"^[A-Za-z0-9](?:[A-Za-z0-9-]{0,37}[A-Za-z0-9])?$")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("manifest", type=Path)
    parser.add_argument("--revision", required=True)
    parser.add_argument("--account-id", required=True)
    parser.add_argument("--region", required=True)
    parser.add_argument("--repository", required=True)
    parser.add_argument("--run-id", required=True, type=int)
    parser.add_argument("--run-attempt", required=True, type=int)
    parser.add_argument("--run-url", required=True)
    parser.add_argument("--workflow-actor", required=True)
    parser.add_argument("--workflow-event", required=True)
    parser.add_argument("--workflow-ref", required=True)
    parser.add_argument("--workflow-sha", required=True)
    parser.add_argument("--workflow-triggering-actor", required=True)
    parser.add_argument("--registry", required=True)
    parser.add_argument("--repository-prefix", required=True)
    parser.add_argument("--sbom-artifact-digest", required=True)
    parser.add_argument("--sbom-dir", required=True, type=Path)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    if not REVISION.fullmatch(args.revision):
        raise AssertionError("revision must be a full lowercase Git SHA")
    if not ACCOUNT_ID.fullmatch(args.account_id):
        raise AssertionError("account ID must contain exactly 12 digits")
    if not REGION.fullmatch(args.region):
        raise AssertionError("AWS region is invalid")
    if not REPOSITORY.fullmatch(args.repository):
        raise AssertionError("source repository is invalid")
    if args.run_id <= 0 or args.run_attempt <= 0:
        raise AssertionError("workflow run identity must be positive")

    manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
    expected_top_level = {
        "schemaVersion",
        "revision",
        "awsAccountId",
        "awsRegion",
        "sourceRepository",
        "workflowRunId",
        "workflowRunAttempt",
        "workflowRunUrl",
        "workflowActor",
        "workflowTriggeringActor",
        "workflowEvent",
        "workflowRef",
        "workflowSha",
        "sbomArtifact",
        "sbomArtifactDigest",
        "images",
    }
    if set(manifest) != expected_top_level or manifest["schemaVersion"] != 8:
        raise AssertionError("release manifest schema is invalid")
    if manifest["revision"] != args.revision:
        raise AssertionError("release manifest revision does not match")
    if manifest["awsAccountId"] != args.account_id or manifest["awsRegion"] != args.region:
        raise AssertionError("release manifest AWS boundary does not match")
    if (
        manifest["sourceRepository"] != args.repository
        or manifest["workflowRunId"] != args.run_id
        or manifest["workflowRunAttempt"] != args.run_attempt
        or manifest["workflowRunUrl"] != args.run_url
    ):
        raise AssertionError("release manifest workflow provenance does not match")
    expected_run_url = f"https://github.com/{args.repository}/actions/runs/{args.run_id}"
    if args.run_url != expected_run_url:
        raise AssertionError("workflow run URL does not match the source repository and run ID")
    for field, value in (
        ("workflowActor", args.workflow_actor),
        ("workflowTriggeringActor", args.workflow_triggering_actor),
    ):
        if not GITHUB_LOGIN.fullmatch(value) or manifest[field] != value:
            raise AssertionError(f"release manifest {field} is invalid")
    if (
        args.workflow_event != "workflow_dispatch"
        or manifest["workflowEvent"] != args.workflow_event
    ):
        raise AssertionError("release manifest workflow event must be workflow_dispatch")
    expected_workflow_ref = (
        f"{args.repository}/.github/workflows/publish-staging-images.yml@refs/heads/main"
    )
    if args.workflow_ref != expected_workflow_ref or manifest["workflowRef"] != args.workflow_ref:
        raise AssertionError("release manifest workflow definition ref does not match main")
    if not REVISION.fullmatch(args.workflow_sha):
        raise AssertionError("workflow definition SHA must be a full lowercase Git SHA")
    if manifest["workflowSha"] != args.workflow_sha:
        raise AssertionError("release manifest workflow definition SHA does not match")
    if manifest["sbomArtifact"] != f"staging-container-sboms-{args.revision}":
        raise AssertionError("release manifest SBOM artifact does not match the revision")
    if not DIGEST.fullmatch(args.sbom_artifact_digest):
        raise AssertionError("expected SBOM artifact digest is invalid")
    if manifest["sbomArtifactDigest"] != args.sbom_artifact_digest:
        raise AssertionError("release manifest SBOM artifact digest does not match")

    images = manifest["images"]
    if not isinstance(images, list) or [image.get("service") for image in images] != list(SERVICES):
        raise AssertionError("release manifest must contain each service exactly once in stable order")
    for image in images:
        if set(image) != {"service", "repository", "digest", "uri", "sbomFile", "sbomSha256"}:
            raise AssertionError("release manifest image schema is invalid")
        service = image["service"]
        repository = f"{args.repository_prefix}/{service}"
        digest = image["digest"]
        if image["repository"] != repository or not DIGEST.fullmatch(digest):
            raise AssertionError(f"release manifest image identity is invalid: {service}")
        if image["uri"] != f"{args.registry}/{repository}@{digest}":
            raise AssertionError(f"release manifest image URI is not digest-pinned: {service}")
        if image["sbomFile"] != f"logitrack-{service}.cdx.json" or not SHA256.fullmatch(
            image["sbomSha256"]
        ):
            raise AssertionError(f"release manifest SBOM identity is invalid: {service}")
        sbom_path = args.sbom_dir / image["sbomFile"]
        if not sbom_path.is_file():
            raise AssertionError(f"release manifest SBOM file is missing: {service}")
        actual_sbom_sha256 = hashlib.sha256(sbom_path.read_bytes()).hexdigest()
        if image["sbomSha256"] != actual_sbom_sha256:
            raise AssertionError(f"release manifest SBOM hash does not match: {service}")

    print("PASS: staging release manifest binds five digest-pinned images to hashed SBOMs")


if __name__ == "__main__":
    main()
