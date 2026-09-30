terraform {
  required_version = ">= 1.16.0, < 2.0.0"
  backend "s3" {
    key          = "production/edge/terraform.tfstate"
    region       = "ap-northeast-2"
    encrypt      = true
    use_lockfile = true
  }
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = "ap-northeast-2"
  default_tags {
    tags = {
      Application = "LogiTrack"
      Environment = "production"
      ManagedBy   = "Terraform"
    }
  }
}

provider "aws" {
  alias  = "global"
  region = "us-east-1"
  default_tags {
    tags = {
      Application = "LogiTrack"
      Environment = "production"
      ManagedBy   = "Terraform"
    }
  }
}
