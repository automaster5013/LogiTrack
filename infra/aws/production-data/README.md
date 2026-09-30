# Production data-plane foundation

This root defines the first production HA boundary and is deliberately separate from the cost-constrained staging host. It creates a dedicated VPC, two private data subnets in distinct Availability Zones, and an encrypted PostgreSQL RDS Multi-AZ instance. The database has 35-day automated backup/PITR retention, deletion protection, final snapshots, KMS rotation, Performance Insights, enhanced monitoring, PostgreSQL log exports, forced TLS, and security-group-only access from the application tier. A pre-created `alarm_topic_arn` is mandatory: RDS availability, backup, failure, failover, low-storage, maintenance, notification, and recovery events plus sustained CPU and free-storage alarms are delivered to that production-owned topic.

This configuration is not applied automatically. Applying it creates ongoing AWS charges and requires a reviewed remote S3 backend, change ticket, production budget, restore drill, application compute tier, and migration/cutover plan. The generated master password remains in RDS-managed Secrets Manager and is never accepted as a Terraform input or written into repository files.

Validation without provisioning:

```bash
terraform -chdir=infra/aws/production-data fmt -check
terraform -chdir=infra/aws/production-data init -backend=false -input=false
terraform -chdir=infra/aws/production-data validate
python scripts/production-data-infra-smoke.py
```

Do not reuse the staging Compose database volume as a production source. Restore a verified logical backup into RDS, validate row counts and application migrations, rehearse rollback, and only then change the production application secret to the RDS endpoint.

AWS references: [RDS for PostgreSQL](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_PostgreSQL.html), [automated backup retention](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_WorkingWithAutomatedBackups.BackupRetention.html), and [Multi-AZ deployments](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Concepts.MultiAZ.html).
