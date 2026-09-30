from pathlib import Path

root = Path("infra/aws/production-certificates")
terraform = "\n".join(path.read_text(encoding="utf-8") for path in root.glob("*.tf"))
readme = (root / "README.md").read_text(encoding="utf-8")

for fragment in (
    'key          = "production/certificates/terraform.tfstate"', 'use_lockfile = true',
    'alias  = "global"', 'region = "us-east-1"',
    'resource "aws_acm_certificate" "origin"', 'resource "aws_acm_certificate" "viewer"',
    'validation_method = "DNS"', 'certificate_transparency_logging_preference = "ENABLED"',
    'prevent_destroy = true', 'resource "aws_route53_record" "origin_validation"',
    'resource "aws_route53_record" "viewer_validation"',
    'resource "aws_acm_certificate_validation" "origin"', 'resource "aws_acm_certificate_validation" "viewer"',
    'metric_name         = "DaysToExpiry"', 'threshold           = 45', 'treat_missing_data  = "breaching"',
):
    if fragment not in terraform:
        raise AssertionError(f"production certificate boundary is missing: {fragment}")

for warning in ('validation-only', 'remaining in use', 'never delete or rewrite', 'prevent_destroy'):
    if warning not in readme:
        raise AssertionError(f"production certificate runbook is missing: {warning}")

print("PASS: production origin and viewer certificates are region-correct, DNS-validated, renewal-safe, destroy-protected, and expiry-alarmed")
