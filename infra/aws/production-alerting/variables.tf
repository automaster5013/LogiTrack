variable "paging_https_endpoint" {
  description = "Approved HTTPS endpoint that confirms both regional and global production alarm subscriptions. Stored in encrypted Terraform state."
  type        = string
  sensitive   = true
  validation {
    condition     = can(regex("^https://[^[:space:]]+$", var.paging_https_endpoint))
    error_message = "paging_https_endpoint must be an HTTPS URL without whitespace."
  }
}

variable "subscription_confirmation_timeout_minutes" {
  description = "Maximum time Terraform waits for the paging receiver to confirm each SNS subscription."
  type        = number
  default     = 5
  validation {
    condition     = var.subscription_confirmation_timeout_minutes >= 1 && var.subscription_confirmation_timeout_minutes <= 60
    error_message = "subscription_confirmation_timeout_minutes must be between 1 and 60."
  }
}
