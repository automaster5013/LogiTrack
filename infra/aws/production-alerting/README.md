# Production alert routing

This independently applied Terraform root creates the two production alarm channels required by the regional data/compute and global edge/certificate roots. Both topics use rotating customer-managed KMS keys, reject insecure transport, and accept CloudWatch alarm publications only from this account and from `logitrack-production-*` alarms in the matching region.

The same approved HTTPS paging receiver is subscribed in Seoul and `us-east-1`. Terraform waits for both confirmations, so an unstaffed notification topic cannot be mistaken for a completed alerting rollout. The endpoint is sensitive but remains in the encrypted remote state; never commit it to a tfvars file.

```powershell
terraform -chdir=infra/aws/production-alerting init -backend-config="bucket=<state-bucket>" -backend-config="dynamodb_table=<lock-table>"
terraform -chdir=infra/aws/production-alerting plan -var="paging_https_endpoint=<approved-https-receiver>" -out=alerting.tfplan
terraform -chdir=infra/aws/production-alerting apply alerting.tfplan
```

Keep the receiver operator available to confirm both subscriptions within the configured timeout. After apply, publish a controlled test notification to each output topic and verify receipt and recovery routing. Feed `regional_alarm_topic_arn` into `production-data` and `production-compute`, and `global_alarm_topic_arn` into `production-certificates` and `production-edge`. Review every downstream plan before applying it.

This root is intentionally validate-only in CI. It creates paid, externally visible AWS resources and must not be applied without an approved paging destination, protected-state bootstrap, cost approval, and an operator-owned cutover window.
