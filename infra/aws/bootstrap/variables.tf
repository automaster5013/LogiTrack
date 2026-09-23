variable "aws_region" {
  description = "AWS region that will contain the staging ECR repositories."
  type        = string

  validation {
    condition     = can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]+$", var.aws_region))
    error_message = "aws_region must be a valid AWS region identifier."
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

variable "github_owner_id" {
  description = "Immutable numeric GitHub user or organization ID used in the customized OIDC subject."
  type        = number
  default     = 247691206

  validation {
    condition     = var.github_owner_id > 0 && floor(var.github_owner_id) == var.github_owner_id
    error_message = "github_owner_id must be a positive integer."
  }
}

variable "github_repository_id" {
  description = "Immutable numeric GitHub repository ID used in the customized OIDC subject."
  type        = number
  default     = 1376500287

  validation {
    condition     = var.github_repository_id > 0 && floor(var.github_repository_id) == var.github_repository_id
    error_message = "github_repository_id must be a positive integer."
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

variable "retained_images" {
  description = "Number of newest images retained in each service repository for staging rollback."
  type        = number
  default     = 30

  validation {
    condition     = var.retained_images >= 10 && var.retained_images <= 200 && floor(var.retained_images) == var.retained_images
    error_message = "retained_images must be an integer between 10 and 200."
  }
}

variable "untagged_image_retention_days" {
  description = "Days to retain untagged images before ECR expires them."
  type        = number
  default     = 7

  validation {
    condition     = var.untagged_image_retention_days >= 1 && var.untagged_image_retention_days <= 30 && floor(var.untagged_image_retention_days) == var.untagged_image_retention_days
    error_message = "untagged_image_retention_days must be an integer between 1 and 30."
  }
}
