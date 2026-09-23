variable "aws_region" {
  description = "AWS region for the staging runtime."
  type        = string
  default     = "ap-northeast-2"
  validation {
    condition     = var.aws_region == "ap-northeast-2"
    error_message = "The reviewed staging design is costed and constrained to ap-northeast-2."
  }
}

variable "domain_name" {
  description = "Public hostname served by the staging host."
  type        = string
  default     = "www.logitrack.kr"
  validation {
    condition     = var.domain_name == "www.logitrack.kr"
    error_message = "This root is intentionally restricted to www.logitrack.kr."
  }
}

variable "hosted_zone_id" {
  description = "Existing Route 53 hosted zone that owns logitrack.kr."
  type        = string
  default     = "Z05031871LL3C3WCCPUJO"
  validation {
    condition     = can(regex("^Z[A-Z0-9]+$", var.hosted_zone_id))
    error_message = "hosted_zone_id must be a Route 53 hosted zone ID."
  }
}

variable "instance_type" {
  description = "Single-host staging instance. linux/amd64 is required by the published images."
  type        = string
  default     = "t3a.medium"
  validation {
    condition     = contains(["t3a.medium", "t3.medium"], var.instance_type)
    error_message = "Only the reviewed 4 GiB amd64 instance types are allowed."
  }
}

variable "root_volume_gib" {
  description = "Encrypted gp3 root volume size."
  type        = number
  default     = 30
  validation {
    condition     = var.root_volume_gib >= 30 && var.root_volume_gib <= 50 && floor(var.root_volume_gib) == var.root_volume_gib
    error_message = "root_volume_gib must be an integer from 30 through 50."
  }
}

variable "monthly_budget_usd" {
  description = "AWS Budgets alert threshold; this is an alert, not a hard service cutoff."
  type        = number
  default     = 70
  validation {
    condition     = var.monthly_budget_usd == 70
    error_message = "The approved test ceiling is fixed at USD 70."
  }
}

variable "budget_alert_email" {
  description = "Email that receives 80% actual and 100% forecast budget alerts."
  type        = string
  sensitive   = true
  validation {
    condition     = can(regex("^[^@[:space:]]+@[^@[:space:]]+\\.[^@[:space:]]+$", var.budget_alert_email))
    error_message = "budget_alert_email must be a valid email address."
  }
}

variable "github_owner" {
  type    = string
  default = "automaster5013"
}
variable "github_owner_id" {
  type    = number
  default = 247691206
}
variable "github_repository" {
  type    = string
  default = "LogiTrack"
}
variable "github_repository_id" {
  type    = number
  default = 1376500287
}
variable "github_environment" {
  type    = string
  default = "staging"
}
variable "repository_prefix" {
  type    = string
  default = "logitrack"
}

variable "secret_parameter_names" {
  description = "Pre-created SSM SecureString names. Values are deliberately outside Terraform state."
  type = object({
    postgres_password              = string
    cognito_authorization_base_url = string
    cognito_issuer_uri             = string
    cognito_client_id              = string
  })
  default = {
    postgres_password              = "/logitrack/staging/postgres-password"
    cognito_authorization_base_url = "/logitrack/staging/cognito-authorization-base-url"
    cognito_issuer_uri             = "/logitrack/staging/cognito-issuer-uri"
    cognito_client_id              = "/logitrack/staging/cognito-client-id"
  }
  validation {
    condition     = alltrue([for name in values(var.secret_parameter_names) : startswith(name, "/logitrack/staging/")])
    error_message = "Every parameter must remain below /logitrack/staging/."
  }
}
