variable "regional_alarm_topic_arn" {
  description = "KMS-encrypted ap-northeast-2 SNS topic created by production-alerting."
  type        = string
  validation {
    condition     = can(regex("^arn:aws:sns:ap-northeast-2:[0-9]{12}:logitrack-production-regional-alerts$", var.regional_alarm_topic_arn))
    error_message = "regional_alarm_topic_arn must be the production regional alert topic in ap-northeast-2."
  }
}

variable "archive_retention_days" {
  description = "Immutable compliance retention before an object can be deleted."
  type        = number
  default     = 400
  validation {
    condition     = var.archive_retention_days >= 400 && var.archive_retention_days <= 3650
    error_message = "archive_retention_days must be between 400 and 3650."
  }
}
