variable "aws_region" {
  description = "AWS region that owns the production Terraform state."
  type        = string
  default     = "ap-northeast-2"

  validation {
    condition     = var.aws_region == "ap-northeast-2"
    error_message = "The reviewed production state design is restricted to ap-northeast-2."
  }
}

variable "state_key" {
  description = "Exact S3 object key used by the production data-plane root."
  type        = string
  default     = "production/data/terraform.tfstate"

  validation {
    condition     = var.state_key == "production/data/terraform.tfstate"
    error_message = "The state access policy is reviewed only for the production data-plane key."
  }
}
