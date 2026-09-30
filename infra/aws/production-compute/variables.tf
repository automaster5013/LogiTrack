variable "aws_region" {
  type    = string
  default = "ap-northeast-2"
  validation {
    condition     = var.aws_region == "ap-northeast-2"
    error_message = "Production compute is restricted to Seoul."
  }
}
variable "vpc_id" {
  type = string
}
variable "private_subnet_ids" {
  type = list(string)
  validation {
    condition     = length(var.private_subnet_ids) == 3
    error_message = "Exactly three private subnets are required."
  }
}
variable "private_route_table_ids" {
  type = list(string)
  validation {
    condition     = length(var.private_route_table_ids) == 3
    error_message = "Exactly three private route tables are required."
  }
}
variable "application_security_group_id" {
  type = string
}
variable "certificate_arn" {
  type = string
}
variable "alarm_topic_arn" {
  type = string
}
variable "api_image" {
  type = string
  validation {
    condition     = can(regex("^[0-9]{12}\\.dkr\\.ecr\\.ap-northeast-2\\.amazonaws\\.com/logitrack-api@sha256:[0-9a-f]{64}$", var.api_image))
    error_message = "api_image must be an immutable production ECR digest URI."
  }
}
variable "analytics_image" {
  type = string
  validation {
    condition     = can(regex("^[0-9]{12}\\.dkr\\.ecr\\.ap-northeast-2\\.amazonaws\\.com/logitrack-analytics@sha256:[0-9a-f]{64}$", var.analytics_image))
    error_message = "analytics_image must be an immutable production ECR digest URI."
  }
}
variable "web_image" {
  type = string
  validation {
    condition     = can(regex("^[0-9]{12}\\.dkr\\.ecr\\.ap-northeast-2\\.amazonaws\\.com/logitrack-web@sha256:[0-9a-f]{64}$", var.web_image))
    error_message = "web_image must be an immutable production ECR digest URI."
  }
}
variable "database_endpoint" {
  type = string
}
variable "database_secret_arn" {
  type      = string
  sensitive = true
}
variable "cache_endpoint" {
  type = string
}
variable "cache_auth_secret_arn" {
  type      = string
  sensitive = true
}
variable "kafka_bootstrap_servers" {
  type      = string
  sensitive = true
}
variable "kafka_scram_secret_arn" {
  type      = string
  sensitive = true
}
variable "cognito_client_id" {
  type = string
}
variable "cognito_issuer_uri" {
  type = string
}
variable "cognito_authorization_base_url" {
  type = string
}
variable "public_origin" {
  type    = string
  default = "https://www.logitrack.kr"
}
