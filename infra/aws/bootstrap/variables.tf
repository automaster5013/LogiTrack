variable "aws_region" {
  description = "AWS region that will contain the staging ECR repositories."
  type        = string

  validation {
    condition     = can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]+$", var.aws_region))
    error_message = "aws_region must be a valid AWS region identifier."
  }
}

variable "github_oidc_provider_arn" {
  description = "ARN of the account's existing token.actions.githubusercontent.com OIDC provider."
  type        = string

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:oidc-provider/token\\.actions\\.githubusercontent\\.com$", var.github_oidc_provider_arn))
    error_message = "github_oidc_provider_arn must identify GitHub's OIDC provider in the target account."
  }
}

variable "github_owner" {
  description = "GitHub organization or user that owns the repository."
  type        = string
  default     = "automaster5013"

  validation {
    condition     = can(regex("^[A-Za-z0-9-]+$", var.github_owner))
    error_message = "github_owner contains unsupported characters."
  }
}

variable "github_repository" {
  description = "GitHub repository allowed to publish images."
  type        = string
  default     = "LogiTrack"

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+$", var.github_repository))
    error_message = "github_repository contains unsupported characters."
  }
}

variable "github_environment" {
  description = "Protected GitHub environment allowed to assume the publisher role."
  type        = string
  default     = "staging"

  validation {
    condition     = var.github_environment == "staging"
    error_message = "The bootstrap role is intentionally restricted to the staging environment."
  }
}

variable "repository_prefix" {
  description = "Prefix for the five LogiTrack ECR repositories."
  type        = string
  default     = "logitrack"

  validation {
    condition     = can(regex("^[a-z0-9]+([._/-][a-z0-9]+)*$", var.repository_prefix))
    error_message = "repository_prefix must be a valid private ECR repository prefix."
  }
}
