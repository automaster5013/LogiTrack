from pathlib import Path


root = Path("infra/aws/production-data")
main = (root / "main.tf").read_text(encoding="utf-8")
variables = (root / "variables.tf").read_text(encoding="utf-8")
versions = (root / "versions.tf").read_text(encoding="utf-8")
readme = (root / "README.md").read_text(encoding="utf-8")
outputs = (root / "outputs.tf").read_text(encoding="utf-8")
application = Path("api/src/main/resources/application.yml").read_text(encoding="utf-8")

required = (
    'count = 3',
    'private_cidrs      = ["10.40.10.0/24", "10.40.20.0/24", "10.40.30.0/24"]',
    'map_public_ip_on_launch = false',
    'resource "aws_route_table" "data"',
    'route_table_id = aws_route_table.data[count.index].id',
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
    'resource "aws_elasticache_replication_group" "cache"',
    'engine         = "valkey"',
    'num_cache_clusters         = 2',
    'multi_az_enabled           = true',
    'automatic_failover_enabled = true',
    'at_rest_encryption_enabled = true',
    'transit_encryption_enabled = true',
    'transit_encryption_mode    = "required"',
    'auth_token_wo              = var.cache_auth_token',
    'auth_token_wo_version      = var.cache_auth_token_version',
    'resource "aws_secretsmanager_secret" "cache_auth"',
    'secret_string_wo         = jsonencode({ password = var.cache_auth_token })',
    'secret_string_wo_version = var.cache_auth_token_version',
    'snapshot_retention_limit = 7',
    'resource "aws_cloudwatch_metric_alarm" "cache_cpu_high"',
    'resource "aws_cloudwatch_metric_alarm" "cache_evictions"',
    'metric_name         = "Evictions"',
    'log_type         = "slow-log"',
    'log_type         = "engine-log"',
    'name  = "rds.force_ssl"',
    'enable_key_rotation     = true',
    'deletion_window_in_days = 30',
    'resource "aws_msk_cluster" "kafka"',
    'sid       = "AccountAdministration"',
    'sid = "CloudWatchLogsEncryption"',
    'identifiers = ["logs.${var.aws_region}.amazonaws.com"]',
    'number_of_broker_nodes = 3',
    'public_access { type = "DISABLED" }',
    'sasl { scram = true }',
    'unauthenticated = false',
    'client_broker = "TLS"',
    'in_cluster    = true',
    'default.replication.factor=3',
    'min.insync.replicas=2',
    'auto.create.topics.enable=false',
    'unclean.leader.election.enable=false',
    'resource "aws_msk_scram_secret_association" "kafka"',
    'secret_string_wo         = jsonencode(',
    'jaas_config = "org.apache.kafka.common.security.scram.ScramLoginModule required',
    'secret_string_wo_version = var.kafka_scram_secret_version',
    'resource "aws_cloudwatch_metric_alarm" "kafka_under_replicated"',
    'resource "aws_cloudwatch_metric_alarm" "kafka_offline_partitions"',
    'resource "aws_cloudwatch_metric_alarm" "kafka_disk_high"',
    'metric_name         = "UnderMinIsrPartitionCount"',
    'metric_name         = "OfflinePartitionsCount"',
    'metric_name         = "KafkaDataLogsDiskUsed"',
    '"Broker ID"    = each.value',
)
for contract in required:
    if contract not in main:
        raise AssertionError(f"production data boundary is missing: {contract}")

if main.count("prevent_destroy = true") < 10:
    raise AssertionError("database, cache, Kafka, KMS keys, secrets, and logs require Terraform destroy protection")
for forbidden in (
    'resource "aws_internet_gateway"',
    'resource "aws_nat_gateway"',
    'resource "aws_eip"',
    '\n  password =',
    'cidr_ipv4',
    '0.0.0.0/0',
    'auth_token              =',
    'client_broker = "PLAINTEXT"',
    'client_broker = "TLS_PLAINTEXT"',
):
    if forbidden in main:
        raise AssertionError(f"production data boundary contains forbidden public or secret configuration: {forbidden}")

for contract in (
    'var.aws_region == "ap-northeast-2"',
    'var.vpc_cidr == "10.40.0.0/16"',
    'contains(["db.t4g.medium", "db.t4g.large"], var.db_instance_class)',
    'arn:aws:sns:ap-northeast-2:',
    'contains(["cache.t4g.small", "cache.t4g.medium"], var.cache_node_type)',
    'contains(["kafka.m7g.large", "kafka.m7g.xlarge"], var.kafka_instance_type)',
    'var.kafka_version == "3.9.x"',
    'ephemeral   = true',
):
    if contract not in variables:
        raise AssertionError(f"production input boundary is missing: {contract}")
if 'version = "~> 6.0"' not in versions or 'backend "s3" {' not in versions:
    raise AssertionError("production data Terraform must pin the provider family and use remote state")
for warning in ("not applied automatically", "ongoing AWS charges", "restore drill", "migration/cutover plan"):
    if warning not in readme:
        raise AssertionError(f"production apply guardrail documentation is missing: {warning}")

for contract in ('output "database_identifier"', 'output "cache_replication_group_id"', 'output "kafka_cluster_arn"'):
    if contract not in outputs:
        raise AssertionError(f"production data post-apply verification output is missing: {contract}")

for setting in (
    'data.redis.port: ${REDIS_PORT:6379}',
    'data.redis.password: ${REDIS_PASSWORD:}',
    'data.redis.ssl.enabled: ${REDIS_SSL_ENABLED:false}',
    'security.protocol: ${KAFKA_SECURITY_PROTOCOL:PLAINTEXT}',
    'sasl.mechanism: ${KAFKA_SASL_MECHANISM:GSSAPI}',
    'sasl.jaas.config: ${KAFKA_SASL_JAAS_CONFIG:}',
):
    if setting not in application:
        raise AssertionError(f"application cannot consume the production cache contract: {setting}")

print("PASS: production PostgreSQL, Valkey, and MSK are private, Multi-AZ, encrypted, observable, and destroy-protected")
