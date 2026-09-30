# Production data-plane foundation

This root defines the first production HA boundary and is deliberately separate from the cost-constrained staging host. It creates a dedicated VPC and two private data subnets in distinct Availability Zones.

PostgreSQL uses an encrypted RDS Multi-AZ instance with 35-day automated backup/PITR retention, deletion protection, final snapshots, KMS rotation, Performance Insights, enhanced monitoring, PostgreSQL log exports, forced TLS, and security-group-only access from the application tier.

SSE fan-out uses a two-node Valkey replication group with Multi-AZ automatic failover, TLS-only transport, encryption at rest, seven-day snapshots, slow/engine logs, and CPU/eviction alarms. `cache_auth_token` is an ephemeral Terraform input connected only to the provider's write-only `auth_token_wo` field, so its value is not persisted in plan or state. Increment `cache_auth_token_version` for an approved rotation and provide both old/new application credentials during the provider's `ROTATE` phase before a later `SET` cutover.

A pre-created `alarm_topic_arn` is mandatory: RDS availability, backup, failure, failover, low-storage, maintenance, notification, and recovery events plus database and cache alarms are delivered to that production-owned topic.

This configuration is not applied automatically. Applying it creates ongoing AWS charges and requires a reviewed remote S3 backend, change ticket, production budget, restore drill, application compute tier, and migration/cutover plan. The generated master password remains in RDS-managed Secrets Manager and is never accepted as a Terraform input or written into repository files.

Validation without provisioning:

```bash
terraform -chdir=infra/aws/production-data fmt -check
terraform -chdir=infra/aws/production-data init -backend=false -input=false
terraform -chdir=infra/aws/production-data validate
python scripts/production-data-infra-smoke.py
```

Do not reuse the staging Compose database volume as a production source. Restore a verified logical backup into RDS, validate row counts and application migrations, rehearse rollback, and only then change the production application secret to the RDS endpoint.

AWS references: [RDS for PostgreSQL](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_PostgreSQL.html), [automated backup retention](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_WorkingWithAutomatedBackups.BackupRetention.html), [RDS Multi-AZ deployments](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Concepts.MultiAZ.html), [ElastiCache Multi-AZ failover](https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/AutoFailover.html), and [ElastiCache AUTH](https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/auth.html).
