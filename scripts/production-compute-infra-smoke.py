from pathlib import Path

root = Path("infra/aws/production-compute")
main = (root / "main.tf").read_text(encoding="utf-8")
variables = (root / "variables.tf").read_text(encoding="utf-8")
versions = (root / "versions.tf").read_text(encoding="utf-8")
readme = (root / "README.md").read_text(encoding="utf-8")

for contract in (
    'count = 3', 'resource "aws_nat_gateway" "az"', 'resource "aws_vpc_endpoint" "interface"',
    'toset(["ecr.api", "ecr.dkr", "logs", "secretsmanager"])', 'resource "aws_vpc_endpoint" "s3"',
    'data "aws_ec2_managed_prefix_list" "cloudfront"', 'data.aws_ec2_managed_prefix_list.cloudfront.id',
    'enable_deletion_protection = true', '"ELBSecurityPolicy-TLS13-1-2-2021-06"',
    'desired_count', 'platform_version', 'enable_execute_command',
    'deployment_minimum_healthy_percent = 100', 'rollback = true', 'assign_public_ip = false',
    'readonlyRootFilesystem = true', 'var.api_image', 'var.analytics_image', 'var.web_image',
    ':username::', ':password::', ':jaas_config::', 'min_capacity', 'max_capacity',
    'name  = "KAFKA_TOPIC_REPLICATION_FACTOR"', 'value = "3"',
    'name  = "KAFKA_TOPIC_MIN_IN_SYNC_REPLICAS"', 'value = "2"',
    'metric_name         = "UnHealthyHostCount"', 'treat_missing_data  = "breaching"',
):
    if contract not in main:
        raise AssertionError(f"production compute boundary is missing: {contract}")

for forbidden in ('assign_public_ip = true', 'enable_execute_command = true', ':latest', 'desired_count          = 1'):
    if forbidden in main:
        raise AssertionError(f"production compute contains forbidden configuration: {forbidden}")

for contract in ('logitrack-api@sha256:', 'logitrack-analytics@sha256:', 'logitrack-web@sha256:', 'length(var.private_subnet_ids) == 3'):
    if contract not in variables:
        raise AssertionError(f"production compute input boundary is missing: {contract}")

for contract in ('production/compute/terraform.tfstate', 'encrypt      = true', 'use_lockfile = true'):
    if contract not in versions:
        raise AssertionError(f"production compute backend is missing: {contract}")

for warning in ('validation-only', 'material ongoing charges', 'failover/load drills', 'all ten Kafka topics', '90-day DLQ retention'):
    if warning not in readme:
        raise AssertionError(f"production compute runbook is missing: {warning}")

print("PASS: production compute is private, three-AZ, digest-pinned, secret-backed, autoscaled, and rollback-protected")
