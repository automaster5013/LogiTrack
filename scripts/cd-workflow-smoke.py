import re
from pathlib import Path

import yaml


WORKFLOW_PATH = Path(".github/workflows/publish-staging-images.yml")
PINNED_ACTION = re.compile(r"^[^@\s]+@[0-9a-f]{40}$")
SERVICES = ("api", "analytics", "simulator", "web", "otel-collector")


def main() -> None:
    source = WORKFLOW_PATH.read_text(encoding="utf-8")
    workflow = yaml.safe_load(source)
    job = workflow.get("jobs", {}).get("publish", {})

    if workflow.get("run-name") != "Publish staging ${{ inputs.revision }}":
        raise AssertionError("staging publication run name must identify the requested revision")
    if not re.search(r"(?m)^on:\s*\n\s+workflow_dispatch:\s*$", source):
        raise AssertionError("staging publication must only be manually dispatched")
    if workflow.get("permissions") != {"contents": "read", "id-token": "write"}:
        raise AssertionError("publication permissions must only allow repository reads and OIDC")
    if job.get("environment") != "staging":
        raise AssertionError("publication must pass through the staging GitHub environment")
    if job.get("runs-on") != "ubuntu-24.04" or job.get("timeout-minutes") != 45:
        raise AssertionError("publication runner and timeout are not bounded")
    if job.get("env") != {
        "ARTIFACT_RETENTION_DAYS": 30,
        "DEPLOYMENT_ENVIRONMENT": "staging",
        "IMAGE_PLATFORM": "linux/amd64",
        "MAX_IMAGE_SIZE_BYTES": 2147483648,
        "AWS_RETRY_MODE": "standard",
        "AWS_MAX_ATTEMPTS": 5,
        "AWS_PAGER": "",
    }:
        raise AssertionError("AWS CLI must use bounded retries without an interactive pager")
    if workflow.get("concurrency", {}).get("cancel-in-progress") is not False:
        raise AssertionError("an in-flight immutable publication must not be cancelled")

    for step in job.get("steps", []):
        action = step.get("uses")
        if action and not PINNED_ACTION.fullmatch(action):
            raise AssertionError(f"publication uses a mutable action reference: {action}")

    credential_steps = [
        step
        for step in job.get("steps", [])
        if str(step.get("uses", "")).startswith("aws-actions/configure-aws-credentials@")
    ]
    if len(credential_steps) != 1:
        raise AssertionError("publication must configure AWS credentials exactly once")
    credential_inputs = credential_steps[0].get("with", {})
    if credential_inputs.get("allowed-account-ids") != "${{ vars.AWS_ACCOUNT_ID }}":
        raise AssertionError("OIDC credentials must be restricted to the configured AWS account")
    if credential_inputs.get("mask-aws-account-id") is not True:
        raise AssertionError("AWS account IDs must be masked in publication logs")
    if credential_inputs.get("retry-max-attempts") != 5:
        raise AssertionError("OIDC role assumption retries must be bounded")
    if credential_inputs.get("action-timeout-s") != 120:
        raise AssertionError("OIDC credential setup must have a bounded timeout")
    if credential_inputs.get("unset-current-credentials") is not True:
        raise AssertionError("OIDC setup must clear inherited AWS credentials")
    if credential_inputs.get("translate-env-variables") is not False:
        raise AssertionError("OIDC setup must only use explicit workflow inputs")

    forbidden = ("secrets.", "latest", "aws-access-key-id", "aws-secret-access-key", "kaiser5013")
    for value in forbidden:
        if value.lower() in source.lower():
            raise AssertionError(f"publication contains forbidden credential or mutable-tag text: {value}")
    required = (
        "vars.AWS_ROLE_ARN",
        "vars.AWS_REGION",
        "vars.AWS_ACCOUNT_ID",
        "vars.ECR_REPOSITORY_PREFIX",
        "git merge-base --is-ancestor",
        "aws sts get-caller-identity --query Account --output text",
        '[[ "$EXPECTED_AWS_ACCOUNT_ID" =~ ^[0-9]{12}$ ]]',
        'actual_account_id" != "$EXPECTED_AWS_ACCOUNT_ID',
        "aws ecr describe-repositories",
        '.tagMutability == "IMMUTABLE" and .scanOnPush == true and .encryptionType == "AES256"',
        "must use immutable tags, scan-on-push, and AES256 encryption",
        "aws ecr get-lifecycle-policy",
        "($rules | length) == 2",
        '.selection.countType == "sinceImagePushed"',
        '.selection.countType == "imageCountMoreThan"',
        "must keep the bounded two-rule staging lifecycle policy",
        "Verify the ECR registry endpoint",
        'expected_registry="$EXPECTED_AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"',
        'ECR_REGISTRY" != "$expected_registry',
        "ECR login resolved to an unexpected registry",
        "aws ecr describe-images",
        'pinned_destination="$ECR_REGISTRY/$repository@$existing_digest"',
        'docker pull "$pinned_destination"',
        'org.opencontainers.image.source="$SOURCE_URL"',
        'published_source" != "$SOURCE_URL',
        'published_revision" != "$REVISION',
        'published_platform" != "$IMAGE_PLATFORM',
        'targets unsupported platform $platform',
        "already exists with verified revision label",
        "returned an invalid existing digest",
        "--severity CRITICAL",
        "scripts/sbom-smoke.py",
        "scripts/release-manifest-smoke.py",
        "workflowRunId: $workflowRunId",
        "workflowRunAttempt: $workflowRunAttempt",
        "workflowActor: $workflowActor",
        "workflowEvent: $workflowEvent",
        "deploymentEnvironment: $deploymentEnvironment",
        "imagePlatform: $imagePlatform",
        "maxImageSizeBytes: $maxImageSizeBytes",
        "workflowTriggeringActor: $workflowTriggeringActor",
        "workflowRef: $workflowRef",
        "workflowSha: $workflowSha",
        "publishedAt: $publishedAt",
        "artifactRetentionDays: $artifactRetentionDays",
        "sbomArtifact: $sbomArtifact",
        "sbomArtifactUrl: $sbomArtifactUrl",
        'sbom_sha256="$(sha256sum "work/sbom/$sbom_file"',
        "sbomFile: $sbomFile",
        "sbomSha256: $sbomSha256",
        "mediaType: $mediaType",
        "sizeBytes: $sizeBytes",
        "imageManifestMediaType",
        "imageSizeInBytes",
        "unsupported manifest media type",
        "size must be between 1 and $MAX_IMAGE_SIZE_BYTES bytes",
    "--sbom-dir work/sbom",
    '--sbom-artifact-digest "$SBOM_ARTIFACT_DIGEST"',
    '--sbom-artifact-url "$SBOM_ARTIFACT_URL"',
    '--run-url "$WORKFLOW_RUN_URL"',
    "WORKFLOW_RUN_URL: ${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}",
    "SBOM_ARTIFACT_DIGEST: ${{ steps.sboms.outputs.artifact-digest }}",
    "RELEASE_MANIFEST_DIGEST: ${{ steps.release-manifest.outputs.artifact-digest }}",
    "RELEASE_MANIFEST_URL: ${{ steps.release-manifest.outputs.artifact-url }}",
    "SBOM_ARTIFACT_URL: ${{ steps.sboms.outputs.artifact-url }}",
    'artifact_url_pattern="^https://github\\.com/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}/artifacts/[0-9]+$"',
    "Record immutable publication summary",
    "ARTIFACT_RETENTION_DAYS: 30",
    "retention-days: ${{ env.ARTIFACT_RETENTION_DAYS }}",
    'echo "- Artifact retention: \\`$ARTIFACT_RETENTION_DAYS days\\`"',
    'echo "- Release manifest artifact digest: \\`$RELEASE_MANIFEST_DIGEST\\`"',
    'echo "- Publication run: [$GITHUB_RUN_ID]($WORKFLOW_RUN_URL), attempt \\`$WORKFLOW_RUN_ATTEMPT\\`"',
    'if ! [[ "$WORKFLOW_RUN_ATTEMPT" =~ ^[1-9][0-9]*$ ]]; then',
    'if ! [[ "$WORKFLOW_SHA" =~ ^[0-9a-f]{40}$ ]]; then',
    "WORKFLOW_SHA: ${{ github.workflow_sha }}",
    "WORKFLOW_REF: ${{ github.workflow_ref }}",
    "WORKFLOW_ACTOR: ${{ github.actor }}",
    "WORKFLOW_EVENT: ${{ github.event_name }}",
    "DEPLOYMENT_ENVIRONMENT: staging",
    "WORKFLOW_TRIGGERING_ACTOR: ${{ github.triggering_actor }}",
    'expected_workflow_ref="$SOURCE_REPOSITORY/.github/workflows/publish-staging-images.yml@refs/heads/main"',
    'if [ "$WORKFLOW_REF" != "$expected_workflow_ref" ]; then',
    '--workflow-ref "$WORKFLOW_REF"',
    '--workflow-actor "$WORKFLOW_ACTOR"',
    '--workflow-event "$WORKFLOW_EVENT"',
    '--artifact-retention-days "$ARTIFACT_RETENTION_DAYS"',
    '--deployment-environment "$DEPLOYMENT_ENVIRONMENT"',
    '--image-platform "$IMAGE_PLATFORM"',
    '--max-image-size-bytes "$MAX_IMAGE_SIZE_BYTES"',
    '--workflow-triggering-actor "$WORKFLOW_TRIGGERING_ACTOR"',
    '--workflow-sha "$WORKFLOW_SHA"',
    '--published-at "$published_at"',
    'published_at="$(date -u +\'%Y-%m-%dT%H:%M:%SZ\')"',
    'echo "published-at=$published_at" >> "$GITHUB_OUTPUT"',
    "PUBLISHED_AT: ${{ steps.release.outputs.published-at }}",
    'echo "- Published at: \\`$PUBLISHED_AT\\`"',
    'echo "- Workflow definition SHA: \\`$WORKFLOW_SHA\\`"',
    'echo "- Workflow definition ref: \\`$WORKFLOW_REF\\`"',
    'echo "- Workflow actor: \\`$WORKFLOW_ACTOR\\`"',
    'echo "- Workflow event: \\`$WORKFLOW_EVENT\\`"',
    'echo "- Deployment environment: \\`$DEPLOYMENT_ENVIRONMENT\\`"',
    'echo "- Image platform: \\`$IMAGE_PLATFORM\\`"',
    'echo "- Maximum image size: \\`$MAX_IMAGE_SIZE_BYTES bytes\\`"',
    'if [ "$DEPLOYMENT_ENVIRONMENT" != "staging" ]; then',
    'if [ "$WORKFLOW_EVENT" != "workflow_dispatch" ]; then',
    'echo "- Triggering actor: \\`$WORKFLOW_TRIGGERING_ACTOR\\`"',
    'if ! [[ "$ARTIFACT_RETENTION_DAYS" =~ ^[1-9][0-9]*$ ]] || [ "$ARTIFACT_RETENTION_DAYS" -gt 90 ]; then',
    'if [ "$WORKFLOW_RUN_URL" != "$GITHUB_SERVER_URL/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID" ]; then',
        "--repository \"$SOURCE_REPOSITORY\"",
        "staging-release-manifest-${{ steps.revision.outputs.sha }}",
    )
    for value in required:
        if value not in source:
            raise AssertionError(f"publication lacks required control: {value}")
    if source.count("retention-days: ${{ env.ARTIFACT_RETENTION_DAYS }}") != 2:
        raise AssertionError("all publication artifacts must share the configured retention period")
    for service in SERVICES:
        if f"logitrack-{service}:$REVISION" not in source:
            raise AssertionError(f"publication does not build the {service} image by commit SHA")

    scan_index = source.index("Generate and validate SBOMs and vulnerability reports")
    push_index = source.index("Push or verify commit-addressed images")
    manifest_index = source.index("Verify published digests and create release manifest")
    manifest_upload_index = source.index("Upload immutable staging release manifest")
    identity_index = source.index("Verify the intended AWS account")
    repository_index = source.index("Validate pre-provisioned ECR repositories")
    registry_index = source.index("Verify the ECR registry endpoint")
    build_index = source.index("Build deployable service images")
    if identity_index >= repository_index:
        raise AssertionError("AWS account identity must be verified before ECR access")
    if registry_index >= build_index:
        raise AssertionError("the ECR registry endpoint must be verified before image builds")
    if scan_index >= push_index:
        raise AssertionError("images can be pushed before supply-chain validation")
    if not push_index < manifest_index < manifest_upload_index:
        raise AssertionError("release manifest must verify ECR digests after push and before upload")
    if re.search(r"\b(ecs|cloudformation|terraform|route53)\b", source, re.IGNORECASE):
        raise AssertionError("image publication must not mutate runtime infrastructure")

    print("PASS: staging image publication is manual, OIDC-only, immutable, and pre-push verified")


if __name__ == "__main__":
    main()
