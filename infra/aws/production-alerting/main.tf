data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_caller_identity" "global" { provider = aws.global }

locals {
  name = "logitrack-production"
  tags = { Application = "LogiTrack", Environment = "production", ManagedBy = "Terraform" }
}

data "aws_iam_policy_document" "regional_key" {
  statement {
    sid       = "AccountAdministration"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }
  statement {
    sid       = "CloudWatchAlarmEncryption"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey*"]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:${data.aws_partition.current.partition}:cloudwatch:ap-northeast-2:${data.aws_caller_identity.current.account_id}:alarm:logitrack-production-*"]
    }
  }
}

resource "aws_kms_key" "regional" {
  description             = "LogiTrack production regional alarm messages"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.regional_key.json
  lifecycle { prevent_destroy = true }
}
resource "aws_kms_alias" "regional" {
  name          = "alias/${local.name}-regional-alerts"
  target_key_id = aws_kms_key.regional.key_id
}
resource "aws_sns_topic" "regional" {
  name              = "${local.name}-regional-alerts"
  kms_master_key_id = aws_kms_key.regional.arn
  lifecycle { prevent_destroy = true }
}

data "aws_iam_policy_document" "regional_topic" {
  statement {
    sid       = "AccountManagement"
    actions   = ["SNS:GetTopicAttributes", "SNS:SetTopicAttributes", "SNS:AddPermission", "SNS:RemovePermission", "SNS:DeleteTopic", "SNS:Subscribe", "SNS:ListSubscriptionsByTopic", "SNS:Publish"]
    resources = [aws_sns_topic.regional.arn]
    principals {
      type        = "AWS"
      identifiers = [data.aws_caller_identity.current.account_id]
    }
  }
  statement {
    sid       = "CloudWatchAlarmPublish"
    actions   = ["SNS:Publish"]
    resources = [aws_sns_topic.regional.arn]
    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:${data.aws_partition.current.partition}:cloudwatch:ap-northeast-2:${data.aws_caller_identity.current.account_id}:alarm:logitrack-production-*"]
    }
  }
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["SNS:*"]
    resources = [aws_sns_topic.regional.arn]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}
resource "aws_sns_topic_policy" "regional" {
  arn    = aws_sns_topic.regional.arn
  policy = data.aws_iam_policy_document.regional_topic.json
}
resource "aws_sns_topic_subscription" "regional_paging" {
  topic_arn                       = aws_sns_topic.regional.arn
  protocol                        = "https"
  endpoint                        = var.paging_https_endpoint
  confirmation_timeout_in_minutes = var.subscription_confirmation_timeout_minutes
  depends_on                      = [aws_sns_topic_policy.regional]
}

data "aws_iam_policy_document" "global_key" {
  provider = aws.global
  statement {
    sid       = "AccountAdministration"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.global.account_id}:root"]
    }
  }
  statement {
    sid       = "CloudWatchAlarmEncryption"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey*"]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.global.account_id]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:${data.aws_partition.current.partition}:cloudwatch:us-east-1:${data.aws_caller_identity.global.account_id}:alarm:logitrack-production-*"]
    }
  }
}
resource "aws_kms_key" "global" {
  provider                = aws.global
  description             = "LogiTrack production global edge alarm messages"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.global_key.json
  lifecycle { prevent_destroy = true }
}
resource "aws_kms_alias" "global" {
  provider      = aws.global
  name          = "alias/${local.name}-global-alerts"
  target_key_id = aws_kms_key.global.key_id
}
resource "aws_sns_topic" "global" {
  provider          = aws.global
  name              = "${local.name}-global-alerts"
  kms_master_key_id = aws_kms_key.global.arn
  lifecycle { prevent_destroy = true }
}

data "aws_iam_policy_document" "global_topic" {
  provider = aws.global
  statement {
    sid       = "AccountManagement"
    actions   = ["SNS:GetTopicAttributes", "SNS:SetTopicAttributes", "SNS:AddPermission", "SNS:RemovePermission", "SNS:DeleteTopic", "SNS:Subscribe", "SNS:ListSubscriptionsByTopic", "SNS:Publish"]
    resources = [aws_sns_topic.global.arn]
    principals {
      type        = "AWS"
      identifiers = [data.aws_caller_identity.global.account_id]
    }
  }
  statement {
    sid       = "CloudWatchAlarmPublish"
    actions   = ["SNS:Publish"]
    resources = [aws_sns_topic.global.arn]
    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.global.account_id]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:${data.aws_partition.current.partition}:cloudwatch:us-east-1:${data.aws_caller_identity.global.account_id}:alarm:logitrack-production-*"]
    }
  }
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["SNS:*"]
    resources = [aws_sns_topic.global.arn]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}
resource "aws_sns_topic_policy" "global" {
  provider = aws.global
  arn      = aws_sns_topic.global.arn
  policy   = data.aws_iam_policy_document.global_topic.json
}
resource "aws_sns_topic_subscription" "global_paging" {
  provider                        = aws.global
  topic_arn                       = aws_sns_topic.global.arn
  protocol                        = "https"
  endpoint                        = var.paging_https_endpoint
  confirmation_timeout_in_minutes = var.subscription_confirmation_timeout_minutes
  depends_on                      = [aws_sns_topic_policy.global]
}
