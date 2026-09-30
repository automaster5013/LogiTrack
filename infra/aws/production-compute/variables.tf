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
variable "cloudfront_origin_verify_header_name" {
  description = "Random secret header name used only between the approved CloudFront distribution and the ALB."
  type        = string
  sensitive   = true
  validation {
    condition     = can(regex("^X-[A-Za-z0-9-]{24,64}$", var.cloudfront_origin_verify_header_name))
    error_message = "Origin verification header name must be a random X- name with 24-64 additional alphanumeric or hyphen characters."
  }
}
variable "cloudfront_origin_verify_header_values" {
  description = "One active, or two overlapping rotation, base64url values sent only by the approved CloudFront distribution in the secret origin header."
  type        = list(string)
  sensitive   = true
  validation {
    condition = (
      length(var.cloudfront_origin_verify_header_values) >= 1 &&
      length(var.cloudfront_origin_verify_header_values) <= 2 &&
      length(distinct(var.cloudfront_origin_verify_header_values)) == length(var.cloudfront_origin_verify_header_values) &&
      alltrue([for value in var.cloudfront_origin_verify_header_values : can(regex("^[A-Za-z0-9_-]{43,128}$", value))])
    )
    error_message = "Provide one active or two distinct rotation values, each 43-128 base64url characters."
  }
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
