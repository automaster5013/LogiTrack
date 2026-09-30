data "aws_caller_identity" "current" {}
data "aws_iam_openid_connect_provider" "github" { url = "https://token.actions.githubusercontent.com" }

locals {
  state_bucket_name = "logitrack-production-tfstate-${data.aws_caller_identity.current.account_id}"
  audit_bucket_name = "logitrack-production-tfstate-audit-${data.aws_caller_identity.current.account_id}"
  state_keys = toset([
    "production/alerting/terraform.tfstate",
    "production/audit/terraform.tfstate",
    "production/certificates/terraform.tfstate",
    "production/compute/terraform.tfstate",
    "production/data/terraform.tfstate",
    "production/edge/terraform.tfstate",
  ])
  state_object_arns = [for key in local.state_keys : "arn:aws:s3:::${local.state_bucket_name}/${key}"]
  lock_object_arns  = [for arn in local.state_object_arns : "${arn}.tflock"]
}

resource "aws_kms_key" "state" {
  description             = "LogiTrack production Terraform state"
  enable_key_rotation     = true
  deletion_window_in_days = 30

  lifecycle { prevent_destroy = true }
}

resource "aws_kms_alias" "state" {
  name          = "alias/logitrack-production-terraform-state"
  target_key_id = aws_kms_key.state.key_id
}

resource "aws_s3_bucket" "audit" {
  bucket        = local.audit_bucket_name
  force_destroy = false

  lifecycle { prevent_destroy = true }
}

resource "aws_s3_bucket_public_access_block" "audit" {
  bucket = aws_s3_bucket.audit.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "audit" {
  bucket = aws_s3_bucket.audit.id
  rule { object_ownership = "BucketOwnerEnforced" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "audit" {
  bucket = aws_s3_bucket.audit.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_s3_bucket_versioning" "audit" {
  bucket = aws_s3_bucket.audit.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_lifecycle_configuration" "audit" {
  bucket = aws_s3_bucket.audit.id

  rule {
    id     = "retain-state-access-audit"
    status = "Enabled"

    filter { prefix = "state-access/" }

    expiration { days = 400 }
    noncurrent_version_expiration { noncurrent_days = 30 }
  }
}

data "aws_iam_policy_document" "audit_bucket" {
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.audit.arn, "${aws_s3_bucket.audit.arn}/*"]
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

  statement {
    sid       = "AllowS3ServerAccessLogs"
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.audit.arn}/state-access/*"]
    principals {
      type        = "Service"
      identifiers = ["logging.s3.amazonaws.com"]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = [aws_s3_bucket.state.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_s3_bucket_policy" "audit" {
  bucket = aws_s3_bucket.audit.id
  policy = data.aws_iam_policy_document.audit_bucket.json
}

resource "aws_s3_bucket" "state" {
  bucket        = local.state_bucket_name
  force_destroy = false

  lifecycle { prevent_destroy = true }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket = aws_s3_bucket.state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "state" {
  bucket = aws_s3_bucket.state.id
  rule { object_ownership = "BucketOwnerEnforced" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    bucket_key_enabled = true
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.state.arn
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_logging" "state" {
  bucket        = aws_s3_bucket.state.id
  target_bucket = aws_s3_bucket.audit.id
  target_prefix = "state-access/"

  depends_on = [aws_s3_bucket_policy.audit]
}

data "aws_iam_policy_document" "state_bucket" {
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.state.arn, "${aws_s3_bucket.state.arn}/*"]
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

resource "aws_s3_bucket_policy" "state" {
  bucket = aws_s3_bucket.state.id
  policy = data.aws_iam_policy_document.state_bucket.json
}

data "aws_iam_policy_document" "backend_access" {
  statement {
    sid       = "ListExactStatePath"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.state.arn]
    condition {
      test     = "StringEquals"
      variable = "s3:prefix"
      values   = concat(tolist(local.state_keys), [for key in local.state_keys : "${key}.tflock"])
    }
  }

  statement {
    sid       = "ReadWriteState"
    actions   = ["s3:GetObject", "s3:PutObject"]
    resources = local.state_object_arns
  }

  statement {
    sid       = "ManageLockFile"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = local.lock_object_arns
  }

  statement {
    sid = "UseStateEncryptionKey"
    actions = [
      "kms:Decrypt",
      "kms:DescribeKey",
      "kms:Encrypt",
      "kms:GenerateDataKey",
    ]
    resources = [aws_kms_key.state.arn]
  }
}

resource "aws_iam_policy" "backend_access" {
  name        = "LogiTrackProductionTerraformStateAccess"
  description = "Least-privilege access to the LogiTrack production Terraform state and lock file"
  policy      = data.aws_iam_policy_document.backend_access.json
}

data "aws_iam_policy_document" "production_plan_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_owner}@${var.github_owner_id}/${var.github_repository}@${var.github_repository_id}:environment:production-plan"]
    }
  }
}

resource "aws_iam_role" "production_plan" {
  name                 = "logitrack-production-terraform-plan"
  description          = "Read-only production planning from the protected GitHub environment"
  assume_role_policy   = data.aws_iam_policy_document.production_plan_assume.json
  max_session_duration = 3600
}

resource "aws_iam_role_policy_attachment" "production_plan_view_only" {
  role       = aws_iam_role.production_plan.name
  policy_arn = "arn:aws:iam::aws:policy/job-function/ViewOnlyAccess"
}

resource "aws_iam_role_policy_attachment" "production_plan_state" {
  role       = aws_iam_role.production_plan.name
  policy_arn = aws_iam_policy.backend_access.arn
}
