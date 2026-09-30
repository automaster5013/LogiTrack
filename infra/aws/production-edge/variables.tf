variable "route53_zone_id" { type = string }
variable "public_hostname" {
  type    = string
  default = "www.logitrack.kr"
  validation {
    condition     = var.public_hostname == "www.logitrack.kr"
    error_message = "The reviewed production viewer hostname is www.logitrack.kr."
  }
}
variable "origin_hostname" {
  type    = string
  default = "origin.logitrack.kr"
  validation {
    condition     = var.origin_hostname == "origin.logitrack.kr"
    error_message = "The reviewed production origin hostname is origin.logitrack.kr."
  }
}
variable "load_balancer_dns_name" { type = string }
variable "load_balancer_zone_id" { type = string }
variable "viewer_certificate_arn" {
  description = "Validated ACM certificate for www.logitrack.kr in us-east-1."
  type        = string
  validation {
    condition     = can(regex("^arn:aws:acm:us-east-1:[0-9]{12}:certificate/[0-9a-f-]+$", var.viewer_certificate_arn))
    error_message = "CloudFront viewer_certificate_arn must be an ACM certificate in us-east-1."
  }
}
variable "global_alarm_topic_arn" {
  description = "Production operations SNS topic in us-east-1 for CloudFront and global WAF alarms."
  type        = string
  validation {
    condition     = can(regex("^arn:aws:sns:us-east-1:[0-9]{12}:[A-Za-z0-9_-]+$", var.global_alarm_topic_arn))
    error_message = "global_alarm_topic_arn must identify a us-east-1 SNS topic."
  }
}
variable "origin_verify_header_name" {
  type      = string
  sensitive = true
  validation {
    condition     = can(regex("^X-[A-Za-z0-9-]{24,64}$", var.origin_verify_header_name))
    error_message = "Origin verification header name must match the production-compute secret name contract."
  }
}
variable "origin_verify_header_value" {
  type      = string
  sensitive = true
  validation {
    condition     = can(regex("^[A-Za-z0-9_-]{43,128}$", var.origin_verify_header_value))
    error_message = "Origin verification value must be 43-128 base64url characters."
  }
}
variable "waf_requests_per_five_minutes" {
  type    = number
  default = 2000
  validation {
    condition     = var.waf_requests_per_five_minutes >= 100 && var.waf_requests_per_five_minutes <= 20000
    error_message = "WAF request ceiling must be between 100 and 20000 per source IP per five minutes."
  }
}
