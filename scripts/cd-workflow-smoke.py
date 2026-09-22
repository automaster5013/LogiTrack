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

    if not re.search(r"(?m)^on:\s*\n\s+workflow_dispatch:\s*$", source):
        raise AssertionError("staging publication must only be manually dispatched")
    if workflow.get("permissions") != {"contents": "read", "id-token": "write"}:
        raise AssertionError("publication permissions must only allow repository reads and OIDC")
    if job.get("environment") != "staging":
        raise AssertionError("publication must pass through the staging GitHub environment")
    if job.get("runs-on") != "ubuntu-24.04" or job.get("timeout-minutes") != 45:
        raise AssertionError("publication runner and timeout are not bounded")
    if job.get("env") != {
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
        "aws ecr describe-images",
        'pinned_destination="$ECR_REGISTRY/$repository@$existing_digest"',
        'docker pull "$pinned_destination"',
        'org.opencontainers.image.source="$SOURCE_URL"',
        'published_source" != "$SOURCE_URL',
        'published_revision" != "$REVISION',
        "already exists with verified revision label",
        "returned an invalid existing digest",
        "--severity CRITICAL",
        "scripts/sbom-smoke.py",
        "scripts/release-manifest-smoke.py",
        "workflowRunId: $workflowRunId",
        "workflowRunAttempt: $workflowRunAttempt",
        "--repository \"$SOURCE_REPOSITORY\"",
        "staging-release-manifest-${{ steps.revision.outputs.sha }}",
    )
    for value in required:
        if value not in source:
            raise AssertionError(f"publication lacks required control: {value}")
    for service in SERVICES:
        if f"logitrack-{service}:$REVISION" not in source:
            raise AssertionError(f"publication does not build the {service} image by commit SHA")

    scan_index = source.index("Generate and validate SBOMs and vulnerability reports")
    push_index = source.index("Push or verify commit-addressed images")
    manifest_index = source.index("Verify published digests and create release manifest")
    manifest_upload_index = source.index("Upload immutable staging release manifest")
    identity_index = source.index("Verify the intended AWS account")
    repository_index = source.index("Validate pre-provisioned ECR repositories")
    if identity_index >= repository_index:
        raise AssertionError("AWS account identity must be verified before ECR access")
    if scan_index >= push_index:
        raise AssertionError("images can be pushed before supply-chain validation")
    if not push_index < manifest_index < manifest_upload_index:
        raise AssertionError("release manifest must verify ECR digests after push and before upload")
    if re.search(r"\b(ecs|cloudformation|terraform|route53)\b", source, re.IGNORECASE):
        raise AssertionError("image publication must not mutate runtime infrastructure")

    print("PASS: staging image publication is manual, OIDC-only, immutable, and pre-push verified")


if __name__ == "__main__":
    main()
