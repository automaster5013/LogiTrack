variable "aws_region" {
  description = "AWS region that owns the production Terraform state."
  type        = string
  default     = "ap-northeast-2"

  validation {
    condition     = var.aws_region == "ap-northeast-2"
    error_message = "The reviewed production state design is restricted to ap-northeast-2."
  }
}

variable "github_owner" {
  description = "GitHub owner name embedded with its immutable ID in the customized OIDC subject."
  type        = string
  default     = "automaster5013"
}

variable "github_owner_id" {
  description = "Immutable numeric GitHub owner ID used in the customized OIDC subject."
  type        = number
  validation {
    condition     = var.github_owner_id > 0 && floor(var.github_owner_id) == var.github_owner_id
    error_message = "github_owner_id must be a positive integer."
  }
}

variable "github_repository" {
  description = "GitHub repository name embedded with its immutable ID in the customized OIDC subject."
  type        = string
  default     = "LogiTrack"
}

variable "github_repository_id" {
  description = "Immutable numeric GitHub repository ID used in the customized OIDC subject."
  type        = number
  validation {
    condition     = var.github_repository_id > 0 && floor(var.github_repository_id) == var.github_repository_id
    error_message = "github_repository_id must be a positive integer."
  }
}
