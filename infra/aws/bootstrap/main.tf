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

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
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

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_ecr_lifecycle_policy" "service" {
  for_each = local.services

  repository = aws_ecr_repository.service[each.key].name
  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after the configured grace period"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = var.untagged_image_retention_days
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Retain the newest images for rollback"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = var.retained_images
        }
        action = {
          type = "expire"
        }
      },
    ]
  })
}

data "aws_iam_policy_document" "publisher_trust" {
  statement {
    sid     = "GitHubStagingEnvironmentOnly"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_owner}@${var.github_owner_id}/${var.github_repository}@${var.github_repository_id}:environment:${var.github_environment}"]
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
      "ecr:BatchGetImage",
      "ecr:BatchCheckLayerAvailability",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeImages",
      "ecr:GetDownloadUrlForLayer",
      "ecr:GetLifecyclePolicy",
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

data "aws_iam_policy_document" "boundary_auditor_trust" {
  statement {
    sid     = "GitHubMainBranchOnly"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_owner}@${var.github_owner_id}/${var.github_repository}@${var.github_repository_id}:ref:refs/heads/main"]
    }
  }
}

resource "aws_iam_role" "boundary_auditor" {
  name                 = "logitrack-staging-boundary-auditor"
  description          = "Read-only GitHub OIDC role for scheduled LogiTrack staging boundary audits"
  assume_role_policy   = data.aws_iam_policy_document.boundary_auditor_trust.json
  max_session_duration = 3600
}

data "aws_iam_policy_document" "boundary_auditor" {
  statement {
    sid    = "ReadStagingControlPlane"
    effect = "Allow"
    actions = [
      "acm:DescribeCertificate", "budgets:ViewBudget", "cloudwatch:DescribeAlarms",
      "cognito-idp:DescribeManagedLoginBrandingByClient", "cognito-idp:DescribeUserPool", "cognito-idp:DescribeUserPoolClient", "cognito-idp:DescribeUserPoolDomain",
      "cognito-idp:GetUserPoolMfaConfig", "cognito-idp:ListGroups", "cognito-idp:ListUserPoolClients", "cognito-idp:ListUserPools", "cognito-idp:ListUsers", "cognito-idp:ListUsersInGroup",
      "dlm:GetLifecyclePolicies", "dlm:GetLifecyclePolicy",
      "ec2:DescribeAddresses", "ec2:DescribeInstanceAttribute", "ec2:DescribeInstances", "ec2:DescribeSecurityGroups", "ec2:DescribeSnapshots", "ec2:DescribeVolumes",
      "ssm:DescribeAssociation", "ssm:DescribeInstanceInformation", "ssm:ListAssociations", "sts:GetCallerIdentity",
    ]
    resources = ["*"]
  }
  statement {
    sid       = "ReadStagingIamBoundaries"
    effect    = "Allow"
    actions   = ["iam:GetRole", "iam:GetRolePolicy", "iam:ListAttachedRolePolicies", "iam:ListRolePolicies"]
    resources = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/logitrack-staging-*"]
  }
  statement {
    sid       = "ReadStagingEcrBoundaries"
    effect    = "Allow"
    actions   = ["ecr:DescribeRepositories", "ecr:GetLifecyclePolicy"]
    resources = values(aws_ecr_repository.service)[*].arn
  }
  statement {
    sid       = "ReadStagingBackupBucket"
    effect    = "Allow"
    actions   = ["s3:GetEncryptionConfiguration", "s3:GetLifecycleConfiguration", "s3:GetBucketPublicAccessBlock", "s3:ListBucket"]
    resources = ["arn:${data.aws_partition.current.partition}:s3:::logitrack-staging-backups-${data.aws_caller_identity.current.account_id}-${var.aws_region}"]
  }
  statement {
    sid       = "ReadStagingBackupObjects"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["arn:${data.aws_partition.current.partition}:s3:::logitrack-staging-backups-${data.aws_caller_identity.current.account_id}-${var.aws_region}/postgres/*"]
  }
  statement {
    sid       = "ReadPublicDnsBoundary"
    effect    = "Allow"
    actions   = ["route53:ListResourceRecordSets"]
    resources = ["arn:${data.aws_partition.current.partition}:route53:::hostedzone/${var.hosted_zone_id}"]
  }
}

resource "aws_iam_role_policy" "boundary_auditor" {
  name   = "audit-logitrack-staging-boundaries"
  role   = aws_iam_role.boundary_auditor.id
  policy = data.aws_iam_policy_document.boundary_auditor.json
}
