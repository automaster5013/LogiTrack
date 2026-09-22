# AWS image publication bootstrap

This Terraform root creates only the five private ECR repositories, their bounded lifecycle policies, and the least-privilege IAM role required by `Publish staging images`. It does not create or update ECS, databases, networking, DNS, certificates, or other runtime infrastructure.

## Prerequisites

1. Select the AWS account and region, then set a monthly cost ceiling before applying anything.
2. Ensure the account already has the GitHub Actions OIDC provider `token.actions.githubusercontent.com`. Supply its ARN; this root deliberately does not own the account-wide provider.
3. Configure remote encrypted Terraform state and locking before the first shared apply. Do not commit state or plan files.
4. Copy `terraform.tfvars.example` to an ignored `terraform.tfvars` and replace the example account ID and region.

## Safe review

```powershell
terraform -chdir=infra/aws/bootstrap init -backend=false
terraform -chdir=infra/aws/bootstrap fmt -check
terraform -chdir=infra/aws/bootstrap validate
terraform -chdir=infra/aws/bootstrap plan -out=bootstrap.tfplan
terraform -chdir=infra/aws/bootstrap show bootstrap.tfplan
```

The plan should contain exactly five immutable, scan-on-push ECR repositories, five lifecycle policies, one IAM role, and one inline role policy. Every repository has Terraform `prevent_destroy` protection, so intentional retirement requires a reviewed code change before a destroy plan can proceed. By default each repository retains its newest 30 images for rollback and expires untagged images after 7 days. The validated inputs allow 10–200 retained images and a 1–30 day untagged grace period. Review the plan before apply. Applying is intentionally a separate operator action because it creates billable external resources and later expires images outside the configured rollback window.

After an approved apply, copy the `github_environment_variables` output (`AWS_ROLE_ARN`, `AWS_REGION`, `AWS_ACCOUNT_ID`, and `ECR_REPOSITORY_PREFIX`) into variables on the protected GitHub `staging` environment. The publication workflow compares the OIDC caller account to `AWS_ACCOUNT_ID` before it accesses ECR. The AWS login email and long-lived access keys must never be stored in Terraform, GitHub variables, or this repository.

Repository deletion is protected by both `prevent_destroy = true` and `force_delete = false`; Terraform refuses a destroy plan unless the guard is deliberately removed, and AWS refuses deletion while images remain. Published tags are immutable, lifecycle expiry is bounded by explicit retention inputs, the publisher can read back only the image metadata needed to create a digest-pinned release manifest, and the role trust policy accepts only OIDC tokens for `automaster5013/LogiTrack` using the `staging` environment.
