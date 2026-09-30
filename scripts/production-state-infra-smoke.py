from pathlib import Path


root = Path("infra/aws/production-state")
main = (root / "main.tf").read_text(encoding="utf-8")
variables = (root / "variables.tf").read_text(encoding="utf-8")
outputs = (root / "outputs.tf").read_text(encoding="utf-8")
readme = (root / "README.md").read_text(encoding="utf-8")
data_versions = Path("infra/aws/production-data/versions.tf").read_text(encoding="utf-8")

for contract in (
    'enable_key_rotation     = true',
    'deletion_window_in_days = 30',
    'resource "aws_s3_bucket" "state"',
    'resource "aws_s3_bucket" "audit"',
    'force_destroy = false',
    'object_ownership = "BucketOwnerEnforced"',
    'block_public_acls       = true',
    'block_public_policy     = true',
    'ignore_public_acls      = true',
    'restrict_public_buckets = true',
    'kms_master_key_id = aws_kms_key.state.arn',
    'sse_algorithm     = "aws:kms"',
    'versioning_configuration { status = "Enabled" }',
    'target_prefix = "state-access/"',
    'variable = "aws:SecureTransport"',
    'values   = ["false"]',
    'actions   = ["s3:GetObject", "s3:PutObject"]',
    'actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]',
    'resources = [local.lock_object_arn]',
    'resource "aws_iam_policy" "backend_access"',
):
    if contract not in main:
        raise AssertionError(f"production state boundary is missing: {contract}")

if main.count("prevent_destroy = true") < 3:
    raise AssertionError("state KMS key and both buckets require destroy protection")

for forbidden in ('acl = "public', '0.0.0.0/0', 'dynamodb_table'):
    if forbidden in main or forbidden in data_versions:
        raise AssertionError(f"production state boundary contains forbidden configuration: {forbidden}")

for contract in (
    'var.aws_region == "ap-northeast-2"',
    'var.state_key == "production/data/terraform.tfstate"',
):
    if contract not in variables:
        raise AssertionError(f"production state input boundary is missing: {contract}")

for contract in ('kms_key_id', 'use_lockfile = true', 'backend_access_policy_arn'):
    if contract not in outputs and contract not in data_versions:
        raise AssertionError(f"backend handoff is missing: {contract}")

for contract in (
    'key          = "production/data/terraform.tfstate"',
    'region       = "ap-northeast-2"',
    'encrypt      = true',
    'use_lockfile = true',
):
    if contract not in data_versions:
        raise AssertionError(f"production data backend is missing: {contract}")

for warning in ("billable AWS resources", "Never use", "Verify a state version"):
    if warning not in readme:
        raise AssertionError(f"production state runbook is missing: {warning}")

print("PASS: production Terraform state is private, versioned, KMS-encrypted, locked, audited, and least-privilege")
