provider "aws" {
  region = var.aws_region
  default_tags {
    tags = { Application = "LogiTrack", Environment = "staging", ManagedBy = "terraform" }
  }
}

data "aws_caller_identity" "current" {}
data "aws_availability_zones" "available" { state = "available" }
data "aws_ssm_parameter" "al2023_ami" { name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64" }
data "aws_iam_openid_connect_provider" "github" { url = "https://token.actions.githubusercontent.com" }

locals {
  parameter_arns = [for name in values(var.secret_parameter_names) : "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter${name}"]
  backup_bucket  = "logitrack-staging-backups-${data.aws_caller_identity.current.account_id}-${var.aws_region}"
}

resource "aws_vpc" "runtime" {
  cidr_block           = "10.42.0.0/24"
  enable_dns_support   = true
  enable_dns_hostnames = true
}
resource "aws_internet_gateway" "runtime" { vpc_id = aws_vpc.runtime.id }
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.runtime.id
  cidr_block              = "10.42.0.0/26"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = false
}
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.runtime.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.runtime.id
  }
}
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "web" {
  name_prefix = "logitrack-staging-web-"
  description = "Public HTTPS ingress only; no SSH or data-tier ports"
  vpc_id      = aws_vpc.runtime.id
  ingress {
    description = "ACME redirect and challenge"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "HTTPS web"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    description = "Package, ECR, Cognito, map and routing egress"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  lifecycle { create_before_destroy = true }
}

data "aws_iam_policy_document" "instance_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}
resource "aws_iam_role" "instance" {
  name               = "logitrack-staging-runtime"
  assume_role_policy = data.aws_iam_policy_document.instance_assume.json
}
resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
data "aws_iam_policy_document" "instance" {
  statement {
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }
  statement {
    actions   = ["ecr:BatchCheckLayerAvailability", "ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer"]
    resources = [for service in ["api", "analytics", "simulator", "web", "otel-collector"] : "arn:aws:ecr:${var.aws_region}:${data.aws_caller_identity.current.account_id}:repository/${var.repository_prefix}/${service}"]
  }
  statement {
    actions   = ["ssm:GetParameter", "ssm:GetParameters"]
    resources = local.parameter_arns
  }
  statement {
    actions   = ["s3:PutObject", "s3:GetObject"]
    resources = ["arn:aws:s3:::${local.backup_bucket}/postgres/*"]
  }
  statement {
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::${local.backup_bucket}"]
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["postgres/*"]
    }
  }
}
resource "aws_iam_role_policy" "instance" {
  name   = "pull-images-and-read-runtime-secrets"
  role   = aws_iam_role.instance.id
  policy = data.aws_iam_policy_document.instance.json
}
resource "aws_iam_instance_profile" "runtime" {
  name = "logitrack-staging-runtime"
  role = aws_iam_role.instance.name
}

resource "aws_instance" "runtime" {
  ami                                  = data.aws_ssm_parameter.al2023_ami.value
  instance_type                        = var.instance_type
  subnet_id                            = aws_subnet.public.id
  vpc_security_group_ids               = [aws_security_group.web.id]
  iam_instance_profile                 = aws_iam_instance_profile.runtime.name
  associate_public_ip_address          = false
  monitoring                           = false
  disable_api_termination              = true
  instance_initiated_shutdown_behavior = "stop"
  user_data_replace_on_change          = true
  user_data                            = file("${path.module}/user-data.sh")
  volume_tags = {
    Name             = "logitrack-staging-root"
    SnapshotSchedule = "logitrack-staging-daily"
  }
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }
  root_block_device {
    encrypted             = true
    volume_type           = "gp3"
    volume_size           = var.root_volume_gib
    delete_on_termination = true
  }
  lifecycle {
    prevent_destroy = true
    # The provider reports this as true after the separately managed EIP is
    # attached, even though the subnet does not auto-assign a public address.
    ignore_changes = [ami, associate_public_ip_address]
  }
  tags = { Name = "logitrack-staging", DeploymentTarget = "logitrack-staging" }
}

resource "aws_cloudwatch_metric_alarm" "system_recovery" {
  alarm_name          = "logitrack-staging-ec2-system-recovery"
  alarm_description   = "Recover the staging EC2 host after two consecutive system status check failures"
  namespace           = "AWS/EC2"
  metric_name         = "StatusCheckFailed_System"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  actions_enabled     = true
  alarm_actions       = ["arn:aws:automate:${var.aws_region}:ec2:recover"]
  dimensions          = { InstanceId = aws_instance.runtime.id }
}

data "aws_iam_policy_document" "snapshot_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["dlm.amazonaws.com"]
    }
  }
}
resource "aws_iam_role" "snapshot" {
  name               = "logitrack-staging-ebs-snapshot"
  assume_role_policy = data.aws_iam_policy_document.snapshot_assume.json
}
data "aws_iam_policy_document" "snapshot" {
  statement {
    actions   = ["ec2:DescribeInstances", "ec2:DescribeVolumes", "ec2:DescribeSnapshots"]
    resources = ["*"]
  }
  statement {
    actions   = ["ec2:CreateSnapshot", "ec2:CreateSnapshots"]
    resources = ["arn:aws:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:volume/*"]
    condition {
      test     = "StringEquals"
      variable = "ec2:ResourceTag/SnapshotSchedule"
      values   = ["logitrack-staging-daily"]
    }
  }
  statement {
    actions   = ["ec2:CreateSnapshot", "ec2:CreateSnapshots", "ec2:CreateTags", "ec2:DeleteSnapshot"]
    resources = ["arn:aws:ec2:${var.aws_region}::snapshot/*"]
  }
}
resource "aws_iam_role_policy" "snapshot" {
  name   = "manage-logitrack-staging-snapshots"
  role   = aws_iam_role.snapshot.id
  policy = data.aws_iam_policy_document.snapshot.json
}
resource "aws_dlm_lifecycle_policy" "runtime" {
  description        = "Daily crash-consistent LogiTrack staging root-volume snapshot"
  execution_role_arn = aws_iam_role.snapshot.arn
  state              = "ENABLED"
  policy_details {
    resource_types = ["VOLUME"]
    target_tags    = { SnapshotSchedule = "logitrack-staging-daily" }
    schedule {
      name      = "Daily snapshots retained for seven days"
      copy_tags = true
      create_rule {
        interval      = 24
        interval_unit = "HOURS"
        times         = ["18:00"]
      }
      retain_rule { count = 7 }
      tags_to_add = {
        BackupType = "crash-consistent"
      }
    }
  }
  depends_on = [aws_iam_role_policy.snapshot]
}

resource "aws_s3_bucket" "backups" {
  bucket        = local.backup_bucket
  force_destroy = false
  lifecycle { prevent_destroy = true }
}
resource "aws_s3_bucket_public_access_block" "backups" {
  bucket                  = aws_s3_bucket.backups.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
resource "aws_s3_bucket_server_side_encryption_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}
resource "aws_s3_bucket_lifecycle_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id
  rule {
    id     = "expire-postgres-backups"
    status = "Enabled"
    filter { prefix = "postgres/" }
    expiration { days = 8 }
    abort_incomplete_multipart_upload { days_after_initiation = 1 }
  }
}
data "aws_iam_policy_document" "backup_bucket" {
  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.backups.arn,
      "${aws_s3_bucket.backups.arn}/*",
    ]
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
    sid       = "DenyUnencryptedUploads"
    effect    = "Deny"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.backups.arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "StringNotEquals"
      variable = "s3:x-amz-server-side-encryption"
      values   = ["AES256"]
    }
  }
}
resource "aws_s3_bucket_policy" "backups" {
  bucket = aws_s3_bucket.backups.id
  policy = data.aws_iam_policy_document.backup_bucket.json
  depends_on = [
    aws_s3_bucket_public_access_block.backups,
    aws_s3_bucket_server_side_encryption_configuration.backups,
  ]
}

resource "aws_ssm_association" "postgres_backup" {
  name                        = "AWS-RunShellScript"
  association_name            = "logitrack-staging-postgres-backup"
  schedule_expression         = "cron(30 18 * * ? *)"
  apply_only_at_cron_interval = true
  compliance_severity         = "HIGH"
  max_concurrency             = "1"
  max_errors                  = "0"
  targets {
    key    = "InstanceIds"
    values = [aws_instance.runtime.id]
  }
  parameters = {
    commands = <<-SCRIPT
      set -euo pipefail
      umask 077
      tmp="$(mktemp /tmp/logitrack-postgres-backup-XXXXXX.dump)"
      container=logitrack-staging-postgres-1
      verify_db="logitrack_restore_verify_$(date -u +%Y%m%d%H%M%S)_$RANDOM"
      cleanup() {
        docker exec -e VERIFY_DB="$verify_db" "$container" sh -ec 'export PGPASSWORD="$POSTGRES_PASSWORD"; dropdb --if-exists --force --username="$POSTGRES_USER" "$VERIFY_DB"' >/dev/null 2>&1 || true
        rm -f "$tmp"
      }
      trap cleanup EXIT
      docker exec "$container" sh -ec 'export PGPASSWORD="$POSTGRES_PASSWORD"; pg_dump --format=custom --username="$POSTGRES_USER" --dbname="$POSTGRES_DB"' >"$tmp"
      test -s "$tmp"
      docker exec -i "$container" pg_restore --list <"$tmp" >/dev/null
      docker exec -e VERIFY_DB="$verify_db" "$container" sh -ec 'export PGPASSWORD="$POSTGRES_PASSWORD"; createdb --username="$POSTGRES_USER" "$VERIFY_DB"'
      docker exec -i -e VERIFY_DB="$verify_db" "$container" sh -ec 'export PGPASSWORD="$POSTGRES_PASSWORD"; pg_restore --exit-on-error --no-owner --no-privileges --username="$POSTGRES_USER" --dbname="$VERIFY_DB"' <"$tmp"
      table_count="$(docker exec -e VERIFY_DB="$verify_db" "$container" sh -ec 'export PGPASSWORD="$POSTGRES_PASSWORD"; psql --username="$POSTGRES_USER" --dbname="$VERIFY_DB" --tuples-only --no-align --command="SELECT count(*) FROM information_schema.tables WHERE table_schema = '\''public'\''"')"
      test "$table_count" -gt 0
      docker exec -e VERIFY_DB="$verify_db" "$container" sh -ec 'export PGPASSWORD="$POSTGRES_PASSWORD"; dropdb --if-exists --force --username="$POSTGRES_USER" "$VERIFY_DB"'
      key="postgres/$(date -u +%Y/%m/%d)/logitrack-$(date -u +%Y%m%dT%H%M%SZ).dump"
      aws s3 cp "$tmp" "s3://${local.backup_bucket}/$key" --sse AES256 --checksum-algorithm SHA256 --only-show-errors
      echo "restored and uploaded encrypted PostgreSQL backup with SHA-256 checksum to $key"
    SCRIPT
  }
  depends_on = [
    aws_iam_role_policy.instance,
    aws_s3_bucket_policy.backups,
    aws_s3_bucket_lifecycle_configuration.backups,
  ]
}

resource "aws_eip" "runtime" {
  domain   = "vpc"
  instance = aws_instance.runtime.id
}
resource "aws_route53_record" "www" {
  zone_id = var.hosted_zone_id
  name    = var.domain_name
  type    = "A"
  ttl     = 60
  records = [aws_eip.runtime.public_ip]
}

data "aws_iam_policy_document" "deployer_trust" {
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
      values   = ["repo:${var.github_owner}@${var.github_owner_id}/${var.github_repository}@${var.github_repository_id}:environment:${var.github_environment}"]
    }
  }
}
resource "aws_iam_role" "deployer" {
  name                 = "logitrack-staging-runtime-deployer"
  max_session_duration = 3600
  assume_role_policy   = data.aws_iam_policy_document.deployer_trust.json
}
data "aws_iam_policy_document" "deployer" {
  statement {
    actions = ["ecr:DescribeImages"]
    resources = [
      for service in ["api", "analytics", "simulator", "web", "otel-collector"] :
      "arn:aws:ecr:${var.aws_region}:${data.aws_caller_identity.current.account_id}:repository/${var.repository_prefix}/${service}"
    ]
  }

  statement {
    actions   = ["ssm:SendCommand"]
    resources = [aws_instance.runtime.arn, "arn:aws:ssm:${var.aws_region}::document/AWS-RunShellScript"]
  }
  statement {
    actions   = ["ssm:GetCommandInvocation", "ssm:ListCommandInvocations"]
    resources = ["*"]
  }
  statement {
    actions   = ["ec2:DescribeInstances", "ssm:DescribeInstanceInformation"]
    resources = ["*"]
  }
}
resource "aws_iam_role_policy" "deployer" {
  name   = "deploy-only-to-logitrack-staging"
  role   = aws_iam_role.deployer.id
  policy = data.aws_iam_policy_document.deployer.json
}

resource "aws_budgets_budget" "monthly" {
  name         = "logitrack-staging-monthly"
  budget_type  = "COST"
  limit_amount = tostring(var.monthly_budget_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.budget_alert_email]
  }
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.budget_alert_email]
  }
}
