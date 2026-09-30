from pathlib import Path


root = Path("infra/aws/production-data")
main = (root / "main.tf").read_text(encoding="utf-8")
variables = (root / "variables.tf").read_text(encoding="utf-8")
versions = (root / "versions.tf").read_text(encoding="utf-8")
readme = (root / "README.md").read_text(encoding="utf-8")

required = (
    'count = 2',
    'map_public_ip_on_launch = false',
    'resource "aws_route_table" "data"',
    'resource "aws_vpc_security_group_ingress_rule" "database_from_application"',
    'referenced_security_group_id = aws_security_group.application.id',
    'from_port                    = 5432',
    'to_port                      = 5432',
    'engine         = "postgres"',
    'manage_master_user_password   = true',
    'master_user_secret_kms_key_id = aws_kms_key.database.arn',
    'storage_encrypted     = true',
    'kms_key_id            = aws_kms_key.database.arn',
    'multi_az               = true',
    'publicly_accessible    = false',
    'backup_retention_period = 35',
    'copy_tags_to_snapshot   = true',
    'deletion_protection       = true',
    'skip_final_snapshot       = false',
    'performance_insights_enabled          = true',
    'enabled_cloudwatch_logs_exports       = ["postgresql", "upgrade"]',
    'monitoring_interval                   = 60',
    'policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"',
    'resource "aws_db_event_subscription" "postgres"',
    '"failover"',
    'resource "aws_cloudwatch_metric_alarm" "database_cpu_high"',
    'resource "aws_cloudwatch_metric_alarm" "database_storage_low"',
    'treat_missing_data  = "breaching"',
    'alarm_actions       = [var.alarm_topic_arn]',
    'name  = "rds.force_ssl"',
    'enable_key_rotation     = true',
    'deletion_window_in_days = 30',
)
for contract in required:
    if contract not in main:
        raise AssertionError(f"production data boundary is missing: {contract}")

if main.count("prevent_destroy = true") < 2:
    raise AssertionError("both the database and its KMS key require Terraform destroy protection")
for forbidden in (
    'resource "aws_internet_gateway"',
    'resource "aws_nat_gateway"',
    'resource "aws_eip"',
    'password =',
    'cidr_ipv4',
    '0.0.0.0/0',
):
    if forbidden in main:
        raise AssertionError(f"production data boundary contains forbidden public or secret configuration: {forbidden}")

for contract in (
    'var.aws_region == "ap-northeast-2"',
    'var.vpc_cidr == "10.40.0.0/16"',
    'contains(["db.t4g.medium", "db.t4g.large"], var.db_instance_class)',
    'arn:aws:sns:ap-northeast-2:',
):
    if contract not in variables:
        raise AssertionError(f"production input boundary is missing: {contract}")
if 'version = "~> 6.0"' not in versions or 'backend "s3" {}' not in versions:
    raise AssertionError("production data Terraform must pin the provider family and use remote state")
for warning in ("not applied automatically", "ongoing AWS charges", "restore drill", "migration/cutover plan"):
    if warning not in readme:
        raise AssertionError(f"production apply guardrail documentation is missing: {warning}")

print("PASS: production PostgreSQL is private, Multi-AZ, encrypted, recoverable, and destroy-protected")
