variable "aws_region" {
  description = "AWS region for the reviewed production data plane."
  type        = string
  default     = "ap-northeast-2"

  validation {
    condition     = var.aws_region == "ap-northeast-2"
    error_message = "The reviewed production data design is restricted to ap-northeast-2."
  }
}

variable "name" {
  description = "Stable production resource prefix."
  type        = string
  default     = "logitrack-production"

  validation {
    condition     = var.name == "logitrack-production"
    error_message = "The reviewed naming and deletion controls require logitrack-production."
  }
}

variable "vpc_cidr" {
  description = "Dedicated production data-plane VPC CIDR."
  type        = string
  default     = "10.40.0.0/16"

  validation {
    condition     = var.vpc_cidr == "10.40.0.0/16"
    error_message = "The reviewed network plan reserves 10.40.0.0/16."
  }
}

variable "db_instance_class" {
  description = "Graviton PostgreSQL instance class; change only after load-test review."
  type        = string
  default     = "db.t4g.medium"

  validation {
    condition     = contains(["db.t4g.medium", "db.t4g.large"], var.db_instance_class)
    error_message = "Only reviewed Graviton production instance classes are allowed."
  }
}

variable "postgres_engine_version" {
  description = "Reviewed PostgreSQL major/minor version."
  type        = string
  default     = "17.6"

  validation {
    condition     = can(regex("^17\\.[0-9]+$", var.postgres_engine_version))
    error_message = "Production must remain on a reviewed PostgreSQL 17 minor release."
  }
}

variable "alarm_topic_arn" {
  description = "Pre-created production SNS topic for database alarms and RDS events."
  type        = string

  validation {
    condition     = can(regex("^arn:aws:sns:ap-northeast-2:[0-9]{12}:[A-Za-z0-9_-]+$", var.alarm_topic_arn))
    error_message = "alarm_topic_arn must identify an ap-northeast-2 SNS topic."
  }
}
