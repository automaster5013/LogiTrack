variable "aws_region" {
  type    = string
  default = "ap-northeast-2"
}
variable "environment" {
  description = "Deployment environment name used in Cognito resource names"
  type        = string
  default     = "test"
  validation {
    condition     = contains(["test", "production"], var.environment)
    error_message = "environment must be either test or production."
  }
}
variable "hosted_zone_id" {
  description = "Route 53 public hosted zone ID for logitrack.kr"
  type        = string
}
variable "auth_domain" {
  type    = string
  default = "auth.logitrack.kr"
}
variable "certificate_arn" {
  description = "ACM certificate ARN for auth.logitrack.kr; Cognito custom domains require a us-east-1 certificate."
  type        = string
  validation {
    condition     = can(regex("^arn:aws:acm:us-east-1:[0-9]{12}:certificate/[0-9a-f-]+$", var.certificate_arn))
    error_message = "certificate_arn must be a us-east-1 ACM certificate ARN."
  }
}
variable "callback_url" {
  type    = string
  default = "https://www.logitrack.kr/auth/callback"
}
variable "logout_url" {
  type    = string
  default = "https://www.logitrack.kr/login"
}
