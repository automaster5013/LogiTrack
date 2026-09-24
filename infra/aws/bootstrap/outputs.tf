output "github_environment_variables" {
  description = "Values to configure on the protected GitHub staging environment."
  value = {
    AWS_ROLE_ARN          = aws_iam_role.image_publisher.arn
    AWS_REGION            = var.aws_region
    AWS_ACCOUNT_ID        = data.aws_caller_identity.current.account_id
    ECR_REPOSITORY_PREFIX = var.repository_prefix
  }
}

output "github_oidc_provider_arn" {
  description = "Account-scoped GitHub Actions OIDC provider used by the publisher role."
  value       = aws_iam_openid_connect_provider.github.arn
}

output "boundary_auditor_role_arn" {
  description = "Read-only main-branch GitHub OIDC role used by scheduled staging boundary audits."
  value       = aws_iam_role.boundary_auditor.arn
}

output "ecr_repository_urls" {
  description = "Immutable repositories used by the staging image publication workflow."
  value       = { for service, repository in aws_ecr_repository.service : service => repository.repository_url }
}

output "ecr_retention" {
  description = "Lifecycle guardrails applied independently to every service repository."
  value = {
    retained_images               = var.retained_images
    untagged_image_retention_days = var.untagged_image_retention_days
  }
}
