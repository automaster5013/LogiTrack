# AWS image publication bootstrap

This Terraform root creates the account-wide GitHub Actions OIDC provider, five private ECR repositories, their bounded lifecycle policies, the least-privilege image publisher role, and a read-only main-branch role for scheduled staging boundary audits. It does not create or update ECS, databases, networking, DNS, certificates, or other runtime infrastructure.

## Prerequisites

1. Select the AWS account and region, then set a monthly cost ceiling before applying anything.
2. Confirm the account does not already have the GitHub Actions OIDC provider `token.actions.githubusercontent.com`; this root owns that account-wide provider to avoid an unmanaged trust dependency.
3. Configure remote encrypted Terraform state and locking before the first shared apply. Do not commit state or plan files.
4. Copy `terraform.tfvars.example` to an ignored `terraform.tfvars` and confirm the region.

## Safe review

```powershell
terraform -chdir=infra/aws/bootstrap init -reconfigure `
  -backend-config="bucket=logitrack-terraform-state-<account-id>" `
  -backend-config="key=bootstrap/test/terraform.tfstate" `
  -backend-config="region=ap-northeast-2" `
  -backend-config="encrypt=true" `
  -backend-config="use_lockfile=true" `
  -backend-config="profile=logitrack-test-admin"
terraform -chdir=infra/aws/bootstrap fmt -check
terraform -chdir=infra/aws/bootstrap validate
terraform -chdir=infra/aws/bootstrap plan -out=bootstrap.tfplan
terraform -chdir=infra/aws/bootstrap show bootstrap.tfplan
```

The plan should contain exactly one GitHub OIDC provider, five immutable scan-on-push ECR repositories, five lifecycle policies, two IAM roles, and two inline role policies. Every repository has Terraform `prevent_destroy` protection, so intentional retirement requires a reviewed code change before a destroy plan can proceed. By default each repository retains its newest 30 images for rollback and expires untagged images after 7 days. The validated inputs allow 10–200 retained images and a 1–30 day untagged grace period. Review the plan before apply. Applying is intentionally a separate operator action because it creates account trust and billable external resources and later expires images outside the configured rollback window.

After an approved apply, copy the `github_environment_variables` output (`AWS_ROLE_ARN`, `AWS_REGION`, `AWS_ACCOUNT_ID`, and `ECR_REPOSITORY_PREFIX`) into variables on the protected GitHub `staging` environment. The publication workflow independently compares the OIDC caller account to `AWS_ACCOUNT_ID` before it accesses ECR. The AWS login email and long-lived access keys must never be stored in Terraform, GitHub variables, or this repository.

Repository deletion is protected by both `prevent_destroy = true` and `force_delete = false`; Terraform refuses a destroy plan unless the guard is deliberately removed, and AWS refuses deletion while images remain. Published tags are immutable and lifecycle expiry is bounded by explicit retention inputs. Before a build, the workflow reads each lifecycle policy and rejects missing, extra, or out-of-range expiry rules. The publisher can read image metadata, lifecycle policy, manifests, and layers only from these five repositories. That read access lets an interrupted publication safely pull and verify an already-published immutable image before reusing it; the role cannot read unrelated repositories. The role trust policy accepts only OIDC tokens for `automaster5013/LogiTrack` using the `staging` environment. The subject uses GitHub's immutable owner and repository IDs, verified through the GitHub API and the rejected token's CloudTrail principal, so account or repository renames cannot transfer this trust.
