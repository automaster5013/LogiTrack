# Production data-plane foundation

This root defines the first production HA boundary and is deliberately separate from the cost-constrained staging host. It creates a dedicated VPC and three private data subnets in distinct Availability Zones.

PostgreSQL uses an encrypted RDS Multi-AZ instance with 35-day automated backup/PITR retention, deletion protection, final snapshots, KMS rotation, Performance Insights, enhanced monitoring, PostgreSQL log exports, forced TLS, and security-group-only access from the application tier.

SSE fan-out uses a two-node Valkey replication group with Multi-AZ automatic failover, TLS-only transport, encryption at rest, seven-day snapshots, slow/engine logs, and CPU/eviction alarms. `cache_auth_token` is an ephemeral Terraform input connected only to the provider's write-only `auth_token_wo` and Secrets Manager `secret_string_wo` fields, so its value is not persisted in plan or state. The runtime reads the `password` JSON key from `cache_auth_secret_arn`. Increment `cache_auth_token_version` to atomically send an approved credential to both services, provide both old/new application credentials during the provider's `ROTATE` phase, and complete a later `SET` cutover.

Durable events use a private three-broker Amazon MSK provisioned cluster spread across three Availability Zones. The cluster enforces TLS plus SASL/SCRAM, encrypts data and its SCRAM secret with a rotating KMS key, disables public and unauthenticated access, disables automatic topic creation and unclean leader election, and sets replication factor 3 with minimum in-sync replicas 2. Broker logs are retained in CloudWatch for 30 days, Prometheus exporters are enabled, and below-minimum ISR partitions, offline partitions, and per-broker high disk usage notify the production alarm topic.

`kafka_scram_username` and `kafka_scram_password` are ephemeral Terraform inputs connected only to Secrets Manager's write-only `secret_string_wo` field. Neither value nor the generated JAAS string is persisted in plan or state. Increment `kafka_scram_secret_version` for an approved rotation. The application tier must set `KAFKA_BOOTSTRAP` from the sensitive output, `KAFKA_SECURITY_PROTOCOL=SASL_SSL`, `KAFKA_SASL_MECHANISM=SCRAM-SHA-512`, and `KAFKA_SASL_JAAS_CONFIG` from the secret's `jaas_config` JSON key; never store the JAAS value in Terraform variables, container definitions, or repository files.

A pre-created `alarm_topic_arn` is mandatory: RDS availability, backup, failure, failover, low-storage, maintenance, notification, and recovery events plus database, cache, and Kafka alarms are delivered to that production-owned topic.

This configuration is not applied automatically. Applying it creates ongoing AWS charges and requires a reviewed remote S3 backend, change ticket, production budget, restore drill, Kafka failover drill, application compute tier, and migration/cutover plan. The generated database master password remains in RDS-managed Secrets Manager and is never accepted as a Terraform input or written into repository files.

Validation without provisioning:

```bash
terraform -chdir=infra/aws/production-data fmt -check
terraform -chdir=infra/aws/production-data init -backend=false -input=false
terraform -chdir=infra/aws/production-data validate
python scripts/production-data-infra-smoke.py
```

Do not reuse the staging Compose database volume as a production source. Restore a verified logical backup into RDS, validate row counts and application migrations, rehearse rollback, and only then change the production application secret to the RDS endpoint.

AWS references: [RDS for PostgreSQL](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_PostgreSQL.html), [automated backup retention](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_WorkingWithAutomatedBackups.BackupRetention.html), [RDS Multi-AZ deployments](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Concepts.MultiAZ.html), [ElastiCache Multi-AZ failover](https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/AutoFailover.html), [ElastiCache AUTH](https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/auth.html), [MSK availability guidance](https://docs.aws.amazon.com/msk/latest/developerguide/version-upgrades-best-practices.html), and [MSK SCRAM authentication](https://docs.aws.amazon.com/msk/latest/developerguide/msk-password-tutorial.html).
