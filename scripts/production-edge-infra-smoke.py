from pathlib import Path

root = Path("infra/aws/production-edge")
text = "\n".join(path.read_text(encoding="utf-8") for path in root.glob("*.tf"))
readme = (root / "README.md").read_text(encoding="utf-8")

required = (
    'key          = "production/edge/terraform.tfstate"', 'use_lockfile = true',
    'alias  = "global"', 'region = "us-east-1"',
    'resource "aws_cloudfront_distribution" "production"', 'http_version     = "http2and3"',
    'retain_on_delete = true',
    'origin_protocol_policy   = "https-only"', 'origin_ssl_protocols     = ["TLSv1.2"]',
    'name  = var.origin_verify_header_name', 'value = var.origin_verify_header_value',
    'default_ttl = 0', 'max_ttl     = 0', 'header_behavior = "allViewer"',
    'viewer_protocol_policy   = "redirect-to-https"', 'minimum_protocol_version = "TLSv1.2_2021"',
    'AWSManagedRulesCommonRuleSet', 'AWSManagedRulesKnownBadInputsRuleSet',
    'AWSManagedRulesAmazonIpReputationList', 'aggregate_key_type = "IP"',
    'resource "aws_route53_record" "viewer_ipv4"', 'resource "aws_route53_record" "viewer_ipv6"',
    'metric_name         = "5xxErrorRate"', 'metric_name         = "BlockedRequests"',
)
for fragment in required:
    if fragment not in text:
        raise AssertionError(f"production edge boundary is missing: {fragment}")

for forbidden in ('viewer_protocol_policy = "allow-all"', 'default_ttl = 86400', 'cloudfront_default_certificate = true'):
    if forbidden in text:
        raise AssertionError(f"production edge contains forbidden configuration: {forbidden}")

for warning in (
    'validation-only', 'disables CloudFront caching', 'persist in the KMS-encrypted protected remote state',
    'direct-origin 403', 'header-name rotation requires an approved maintenance window',
):
    if warning not in readme:
        raise AssertionError(f"production edge runbook is missing: {warning}")

print("PASS: production CloudFront edge is TLS-only, no-cache, origin-verified, globally WAF-protected, dual-stack, and alarmed")
