variable "route53_zone_id" { type = string }
variable "origin_hostname" {
  type    = string
  default = "origin.logitrack.kr"
  validation {
    condition     = var.origin_hostname == "origin.logitrack.kr"
    error_message = "The reviewed origin certificate name is origin.logitrack.kr."
  }
}
variable "viewer_hostname" {
  type    = string
  default = "www.logitrack.kr"
  validation {
    condition     = var.viewer_hostname == "www.logitrack.kr"
    error_message = "The reviewed viewer certificate name is www.logitrack.kr."
  }
}
variable "regional_alarm_topic_arn" {
  type = string
  validation {
    condition     = can(regex("^arn:aws:sns:ap-northeast-2:[0-9]{12}:[A-Za-z0-9_-]+$", var.regional_alarm_topic_arn))
    error_message = "regional_alarm_topic_arn must identify a Seoul SNS topic."
  }
}
variable "global_alarm_topic_arn" {
  type = string
  validation {
    condition     = can(regex("^arn:aws:sns:us-east-1:[0-9]{12}:[A-Za-z0-9_-]+$", var.global_alarm_topic_arn))
    error_message = "global_alarm_topic_arn must identify a us-east-1 SNS topic."
  }
}
