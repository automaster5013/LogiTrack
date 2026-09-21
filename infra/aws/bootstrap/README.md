# AWS image publication bootstrap

This Terraform root creates only the five private ECR repositories and the least-privilege IAM role required by `Publish staging images`. It does not create or update ECS, databases, networking, DNS, certificates, or other runtime infrastructure.

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

The plan should contain exactly five immutable, scan-on-push ECR repositories, one IAM role, and one inline role policy. Review it before apply. Applying is intentionally a separate operator action because it creates billable external resources.

After an approved apply, copy the `github_environment_variables` output (`AWS_ROLE_ARN`, `AWS_REGION`, `AWS_ACCOUNT_ID`, and `ECR_REPOSITORY_PREFIX`) into variables on the protected GitHub `staging` environment. The publication workflow compares the OIDC caller account to `AWS_ACCOUNT_ID` before it accesses ECR. The AWS login email and long-lived access keys must never be stored in Terraform, GitHub variables, or this repository.

Repository deletion is protected by `force_delete = false`; Terraform cannot remove a non-empty repository. Published tags are immutable, the publisher can read back only the image metadata needed to create a digest-pinned release manifest, and the role trust policy accepts only OIDC tokens for `automaster5013/LogiTrack` using the `staging` environment.
