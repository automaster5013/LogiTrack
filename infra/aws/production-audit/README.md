# Production audit trail

This validate-only root creates a KMS-encrypted, multi-Region CloudTrail for all management events. It enables global-service events and digest validation, delivers a monitoring copy to an encrypted CloudWatch Logs group, and retains the authoritative S3 archive under versioning and S3 Object Lock compliance mode for at least 400 days. Objects transition to Glacier Instant Retrieval after 90 days and expire after seven years.

Root-account activity triggers immediately and ten access-denied events within five minutes trigger the regional production paging topic. The S3 bucket, KMS key, log group, and trail are protected from Terraform destroy.

Apply this root after `production-state` and `production-alerting`. Review the compliance retention with legal/security owners before the first apply: Object Lock compliance retention cannot be shortened or bypassed, even by the root user. Use an approved plan and verify `aws cloudtrail get-trail-status`, digest validation, a controlled denied request, and receipt by the paging receiver.
