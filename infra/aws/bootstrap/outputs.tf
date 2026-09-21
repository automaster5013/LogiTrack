output "github_environment_variables" {
  description = "Values to configure on the protected GitHub staging environment."
  value = {
    AWS_ROLE_ARN          = aws_iam_role.image_publisher.arn
    AWS_REGION            = var.aws_region
    AWS_ACCOUNT_ID        = data.aws_caller_identity.current.account_id
    ECR_REPOSITORY_PREFIX = var.repository_prefix
  }
}

output "ecr_repository_urls" {
  description = "Immutable repositories used by the staging image publication workflow."
  value       = { for service, repository in aws_ecr_repository.service : service => repository.repository_url }
}
