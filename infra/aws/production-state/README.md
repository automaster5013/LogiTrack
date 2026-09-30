# Production Terraform state bootstrap

This root creates the protected remote-state boundary required before applying the production alerting, audit, certificate, data, compute, and edge roots. It deliberately keeps local bootstrap state: an operator applies it once from an encrypted, access-controlled workstation, records the outputs, and secures that small bootstrap state in the approved operations vault.

The production state bucket has public access blocked, bucket-owner-enforced ownership, versioning, a rotating customer-managed KMS key, S3-native lock-file support, TLS-only access, destroy protection, and server access logs written to a separate protected audit bucket. Audit objects are retained for 400 days. The generated IAM policy grants access only to the six reviewed state objects, their `.tflock` files, and the state KMS key; it grants no prefix-wide wildcard. The bootstrap also creates a view-only GitHub OIDC plan role whose customized subject is restricted to the immutable owner/repository IDs and the `production-plan` environment. AWS `ViewOnlyAccess` exposes basic resource metadata rather than storage contents, while the separate backend policy permits only the reviewed state/lock objects. The role cannot apply AWS resource mutations.

Validate without provisioning:

```bash
terraform -chdir=infra/aws/production-state fmt -check
terraform -chdir=infra/aws/production-state init -backend=false -input=false
terraform -chdir=infra/aws/production-state validate
python scripts/production-state-infra-smoke.py
```

Applying creates billable AWS resources and must use an approved production change ticket and administrator session. Supply the immutable GitHub owner and repository IDs used by the account's customized OIDC subject:

```bash
terraform -chdir=infra/aws/production-state apply
terraform -chdir=infra/aws/production-state output -json backend_configs
```

Create a temporary backend configuration file for each named root from that output without committing it, then initialize the matching root with `terraform -chdir=infra/aws/production-<root> init -migrate-state -backend-config=<temporary-file>`. Stop if Terraform proposes a different key, bucket, region, or KMS key. Never use `-force-copy`, `-lock=false`, or `force-unlock` during routine operations. Verify a state version can be retrieved for each root before the first production apply.

Configure a GitHub `production-plan` environment with required reviewers, prevent self-review and administrator bypass, restrict it to `main`, and set these values from the bootstrap output and the approved offline plan-encryption key:

- variable `PRODUCTION_AWS_ACCOUNT_ID`
- variable `PRODUCTION_TERRAFORM_PLAN_ROLE_ARN`
- variable `PRODUCTION_PLAN_GPG_PUBLIC_KEY_B64`
- variable `PRODUCTION_PLAN_GPG_FINGERPRINT`
- secret `PRODUCTION_TFVARS_BY_ROOT`, a JSON object keyed by the six root names

The manual `Production Terraform plan evidence` workflow accepts only the current full `main` SHA. It uploads a seven-day artifact containing a GPG-encrypted binary plan and a sanitized digest/count summary, then signs both with a GitHub artifact attestation. It never uploads the plaintext plan, variables, backend configuration, or `terraform show` JSON and has no apply step. Keep the matching private GPG key outside GitHub.

References: [Terraform S3 backend and lock file](https://developer.hashicorp.com/terraform/language/backend/s3), [Terraform sensitive state guidance](https://developer.hashicorp.com/terraform/language/manage-sensitive-data), and [S3 versioning](https://docs.aws.amazon.com/AmazonS3/latest/userguide/Versioning.html).
