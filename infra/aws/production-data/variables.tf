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

variable "cache_node_type" {
  description = "Reviewed production Valkey node class."
  type        = string
  default     = "cache.t4g.small"

  validation {
    condition     = contains(["cache.t4g.small", "cache.t4g.medium"], var.cache_node_type)
    error_message = "Only reviewed Graviton cache node classes are allowed."
  }
}

variable "cache_auth_token" {
  description = "ElastiCache AUTH token supplied only during an approved apply; never stored in state."
  type        = string
  sensitive   = true
  ephemeral   = true

  validation {
    condition = (
      can(regex("^[A-Za-z0-9!&#$^<>-]{32,128}$", var.cache_auth_token)) &&
      can(regex("[A-Z]", var.cache_auth_token)) &&
      can(regex("[a-z]", var.cache_auth_token)) &&
      can(regex("[0-9]", var.cache_auth_token)) &&
      can(regex("[!&#$^<>-]", var.cache_auth_token))
    )
    error_message = "cache_auth_token must be 32-128 allowed characters and include upper, lower, digit, and symbol classes."
  }
}

variable "cache_auth_token_version" {
  description = "Increment to send an approved write-only AUTH token rotation."
  type        = number
  default     = 1

  validation {
    condition     = var.cache_auth_token_version >= 1 && floor(var.cache_auth_token_version) == var.cache_auth_token_version
    error_message = "cache_auth_token_version must be a positive integer."
  }
}

variable "kafka_instance_type" {
  description = "Reviewed production MSK broker class."
  type        = string
  default     = "kafka.m7g.large"

  validation {
    condition     = contains(["kafka.m7g.large", "kafka.m7g.xlarge"], var.kafka_instance_type)
    error_message = "Only reviewed Graviton MSK broker classes are allowed."
  }
}

variable "kafka_version" {
  description = "Reviewed Amazon MSK Kafka version."
  type        = string
  default     = "3.9.x"

  validation {
    condition     = var.kafka_version == "3.9.x"
    error_message = "Production must remain on the reviewed MSK Kafka 3.9 release line."
  }
}

variable "kafka_scram_username" {
  description = "MSK SCRAM username supplied only during an approved apply."
  type        = string
  sensitive   = true
  ephemeral   = true

  validation {
    condition     = can(regex("^[A-Za-z0-9._-]{3,64}$", var.kafka_scram_username))
    error_message = "kafka_scram_username must be 3-64 safe identifier characters."
  }
}

variable "kafka_scram_password" {
  description = "MSK SCRAM password supplied only during an approved apply; never stored in state."
  type        = string
  sensitive   = true
  ephemeral   = true

  validation {
    condition = (
      can(regex("^[A-Za-z0-9!#$%&*+,-./:;<=>?@^_`{|}~]{32,128}$", var.kafka_scram_password)) &&
      can(regex("[A-Z]", var.kafka_scram_password)) &&
      can(regex("[a-z]", var.kafka_scram_password)) &&
      can(regex("[0-9]", var.kafka_scram_password)) &&
      can(regex("[!#$%&*+,-./:;<=>?@^_`{|}~]", var.kafka_scram_password))
    )
    error_message = "kafka_scram_password must be 32-128 allowed characters and include upper, lower, digit, and symbol classes."
  }
}

variable "kafka_scram_secret_version" {
  description = "Increment to send an approved write-only MSK SCRAM credential rotation."
  type        = number
  default     = 1

  validation {
    condition     = var.kafka_scram_secret_version >= 1 && floor(var.kafka_scram_secret_version) == var.kafka_scram_secret_version
    error_message = "kafka_scram_secret_version must be a positive integer."
  }
}
