# Production Terraform state bootstrap

This root creates the protected remote-state boundary required before applying `infra/aws/production-data`. It deliberately keeps local bootstrap state: an operator applies it once from an encrypted, access-controlled workstation, records the outputs, and secures that small bootstrap state in the approved operations vault.

The production state bucket has public access blocked, bucket-owner-enforced ownership, versioning, a rotating customer-managed KMS key, S3-native lock-file support, TLS-only access, destroy protection, and server access logs written to a separate protected audit bucket. Audit objects are retained for 400 days. The generated IAM policy grants access only to `production/data/terraform.tfstate`, its `.tflock`, and the state KMS key; attach it only to the approved production Terraform operator role.

Validate without provisioning:

```bash
terraform -chdir=infra/aws/production-state fmt -check
terraform -chdir=infra/aws/production-state init -backend=false -input=false
terraform -chdir=infra/aws/production-state validate
python scripts/production-state-infra-smoke.py
```

Applying creates billable AWS resources and must use an approved production change ticket and administrator session:

```bash
terraform -chdir=infra/aws/production-state apply
terraform -chdir=infra/aws/production-state output -json backend_config
```

Create a temporary backend configuration file from that output without committing it, then initialize the data root with `terraform -chdir=infra/aws/production-data init -migrate-state -backend-config=<temporary-file>`. Stop if Terraform proposes a different key, bucket, region, or KMS key. Never use `-force-copy`, `-lock=false`, or `force-unlock` during routine operations. Verify a state version can be retrieved before the first production apply.

References: [Terraform S3 backend and lock file](https://developer.hashicorp.com/terraform/language/backend/s3), [Terraform sensitive state guidance](https://developer.hashicorp.com/terraform/language/manage-sensitive-data), and [S3 versioning](https://docs.aws.amazon.com/AmazonS3/latest/userguide/Versioning.html).
