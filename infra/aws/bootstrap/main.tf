provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Application = "LogiTrack"
      Environment = "staging"
      ManagedBy   = "terraform"
    }
  }
}

locals {
  services = toset([
    "api",
    "analytics",
    "simulator",
    "web",
    "otel-collector",
  ])
}

resource "aws_ecr_repository" "service" {
  for_each = local.services

  name                 = "${var.repository_prefix}/${each.key}"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = false

  encryption_configuration {
    encryption_type = "AES256"
  }

  image_scanning_configuration {
    scan_on_push = true
  }
}

data "aws_iam_policy_document" "publisher_trust" {
  statement {
    sid     = "GitHubStagingEnvironmentOnly"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.github_oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_owner}/${var.github_repository}:environment:${var.github_environment}"]
    }
  }
}

resource "aws_iam_role" "image_publisher" {
  name                 = "logitrack-staging-image-publisher"
  description          = "GitHub OIDC role for publishing verified LogiTrack staging images"
  assume_role_policy   = data.aws_iam_policy_document.publisher_trust.json
  max_session_duration = 3600
}

data "aws_iam_policy_document" "publisher" {
  statement {
    sid       = "ReadRepositoryMetadata"
    effect    = "Allow"
    actions   = ["ecr:DescribeRepositories"]
    resources = ["*"]
  }

  statement {
    sid       = "AuthenticateToEcr"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid    = "PublishVerifiedImages"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:CompleteLayerUpload",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
    ]
    resources = values(aws_ecr_repository.service)[*].arn
  }
}

resource "aws_iam_role_policy" "image_publisher" {
  name   = "publish-logitrack-staging-images"
  role   = aws_iam_role.image_publisher.id
  policy = data.aws_iam_policy_document.publisher.json
}
