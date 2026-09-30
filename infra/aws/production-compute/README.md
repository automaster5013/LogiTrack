# Production compute foundation

This root creates the reviewed production application tier on the VPC and private subnets from `production-data`. It runs three private Fargate API tasks and three private web tasks across three Availability Zones. Each API task includes its analytics sidecar, while Cloud Map gives web tasks a private multi-value API endpoint.

Only an HTTPS Application Load Balancer is public, and its ingress is restricted to the AWS-managed CloudFront origin-facing prefix list. Tasks receive no public IP. Three zone-local NAT gateways preserve outbound availability for Cognito and the contracted routing provider; ECR API/Docker, S3 image layers, CloudWatch Logs, and Secrets Manager use private VPC endpoints. Images must be ECR digest URIs.

The ECS services use Fargate platform 1.4.0, a minimum of three tasks, 100% rolling-update health, deployment circuit-breaker rollback, CPU target tracking, read-only root filesystems, disabled ECS Exec, 30-day logs, enhanced Container Insights, and an unhealthy-target alarm. Database, Valkey, and Kafka credentials are injected from exact Secrets Manager JSON keys and are never Terraform variables containing plaintext secrets.

Every API replica enables the daily KPI projection writer. The refresh transaction takes a PostgreSQL transaction-scoped advisory lock before doing any work, so at most one replica performs each refresh while the others record a `logitrack.kpi.projection.refresh.skipped` metric. This avoids making a singleton ECS service an availability dependency while preventing duplicate full-range projection work.

This root is validation-only until the production budget, CloudFront origin configuration, ACM certificate, remote-state migration, data plane, topic creation, database migration, and failover/load drills are approved. Applying creates three NAT gateways and continuously running Fargate/ALB resources with material ongoing charges.

```bash
terraform -chdir=infra/aws/production-compute fmt -check
terraform -chdir=infra/aws/production-compute init -backend=false -input=false
terraform -chdir=infra/aws/production-compute validate
python scripts/production-compute-infra-smoke.py
```

References: [Fargate task networking](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/fargate-task-networking.html), [ECS PrivateLink endpoints](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/vpc-endpoints.html), [Secrets Manager JSON-key injection](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/secrets-envvar-secrets-manager.html), and [deployment circuit breaker](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/deployment-circuit-breaker.html).
