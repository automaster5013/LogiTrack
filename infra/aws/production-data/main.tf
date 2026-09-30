data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  availability_zones = slice(data.aws_availability_zones.available.names, 0, 2)
  private_cidrs      = ["10.40.10.0/24", "10.40.20.0/24"]
}

resource "aws_vpc" "production" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = var.name }
}

resource "aws_subnet" "data" {
  count = 2

  vpc_id                  = aws_vpc.production.id
  availability_zone       = local.availability_zones[count.index]
  cidr_block              = local.private_cidrs[count.index]
  map_public_ip_on_launch = false

  tags = { Name = "${var.name}-data-${count.index + 1}" }
}

resource "aws_route_table" "data" {
  vpc_id = aws_vpc.production.id
  tags   = { Name = "${var.name}-data-private" }
}

resource "aws_route_table_association" "data" {
  count = 2

  subnet_id      = aws_subnet.data[count.index].id
  route_table_id = aws_route_table.data.id
}

resource "aws_security_group" "application" {
  name        = "${var.name}-application"
  description = "Attach only to the production application compute tier"
  vpc_id      = aws_vpc.production.id

  tags = { Name = "${var.name}-application" }
}

resource "aws_security_group" "database" {
  name        = "${var.name}-database"
  description = "PostgreSQL only from the production application tier"
  vpc_id      = aws_vpc.production.id

  tags = { Name = "${var.name}-database" }
}

resource "aws_vpc_security_group_egress_rule" "application_to_database" {
  security_group_id            = aws_security_group.application.id
  referenced_security_group_id = aws_security_group.database.id
  description                  = "PostgreSQL only"
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "database_from_application" {
  security_group_id            = aws_security_group.database.id
  referenced_security_group_id = aws_security_group.application.id
  description                  = "PostgreSQL from application security group"
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
}

resource "aws_security_group" "cache" {
  name        = "${var.name}-cache"
  description = "Valkey TLS only from the production application tier"
  vpc_id      = aws_vpc.production.id
  tags        = { Name = "${var.name}-cache" }
}

resource "aws_vpc_security_group_egress_rule" "application_to_cache" {
  security_group_id            = aws_security_group.application.id
  referenced_security_group_id = aws_security_group.cache.id
  description                  = "Valkey TLS only"
  from_port                    = 6379
  to_port                      = 6379
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "cache_from_application" {
  security_group_id            = aws_security_group.cache.id
  referenced_security_group_id = aws_security_group.application.id
  description                  = "Valkey TLS from application security group"
  from_port                    = 6379
  to_port                      = 6379
  ip_protocol                  = "tcp"
}

resource "aws_db_subnet_group" "production" {
  name       = var.name
  subnet_ids = aws_subnet.data[*].id
  tags       = { Name = var.name }
}

resource "aws_kms_key" "database" {
  description             = "LogiTrack production PostgreSQL and managed master secret"
  enable_key_rotation     = true
  deletion_window_in_days = 30

  lifecycle { prevent_destroy = true }
}

resource "aws_kms_alias" "database" {
  name          = "alias/${var.name}-database"
  target_key_id = aws_kms_key.database.key_id
}

resource "aws_kms_key" "cache" {
  description             = "LogiTrack production Valkey data and snapshots"
  enable_key_rotation     = true
  deletion_window_in_days = 30

  lifecycle { prevent_destroy = true }
}

resource "aws_kms_alias" "cache" {
  name          = "alias/${var.name}-cache"
  target_key_id = aws_kms_key.cache.key_id
}

resource "aws_elasticache_subnet_group" "production" {
  name       = var.name
  subnet_ids = aws_subnet.data[*].id
}

resource "aws_cloudwatch_log_group" "cache_slow" {
  name              = "/aws/elasticache/${var.name}/slow-log"
  retention_in_days = 30

  lifecycle { prevent_destroy = true }
}

resource "aws_cloudwatch_log_group" "cache_engine" {
  name              = "/aws/elasticache/${var.name}/engine-log"
  retention_in_days = 30

  lifecycle { prevent_destroy = true }
}

resource "aws_elasticache_replication_group" "cache" {
  replication_group_id = "logitrack-production"
  description          = "LogiTrack production SSE fan-out"

  engine         = "valkey"
  engine_version = "8.2"
  node_type      = var.cache_node_type
  port           = 6379

  num_cache_clusters         = 2
  multi_az_enabled           = true
  automatic_failover_enabled = true
  auto_minor_version_upgrade = true

  subnet_group_name  = aws_elasticache_subnet_group.production.name
  security_group_ids = [aws_security_group.cache.id]

  at_rest_encryption_enabled = true
  kms_key_id                 = aws_kms_key.cache.arn
  transit_encryption_enabled = true
  transit_encryption_mode    = "required"
  auth_token_wo              = var.cache_auth_token
  auth_token_wo_version      = var.cache_auth_token_version
  auth_token_update_strategy = "ROTATE"

  snapshot_retention_limit = 7
  snapshot_window          = "17:00-18:00"
  maintenance_window       = "sun:18:00-sun:19:00"
  apply_immediately        = false
  notification_topic_arn   = var.alarm_topic_arn

  log_delivery_configuration {
    destination      = aws_cloudwatch_log_group.cache_slow.name
    destination_type = "cloudwatch-logs"
    log_format       = "json"
    log_type         = "slow-log"
  }

  log_delivery_configuration {
    destination      = aws_cloudwatch_log_group.cache_engine.name
    destination_type = "cloudwatch-logs"
    log_format       = "json"
    log_type         = "engine-log"
  }

  lifecycle { prevent_destroy = true }
}

resource "aws_cloudwatch_metric_alarm" "cache_cpu_high" {
  alarm_name          = "${var.name}-cache-engine-cpu-high"
  namespace           = "AWS/ElastiCache"
  metric_name         = "EngineCPUUtilization"
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 5
  datapoints_to_alarm = 3
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = 80
  treat_missing_data  = "breaching"
  alarm_actions       = [var.alarm_topic_arn]
  ok_actions          = [var.alarm_topic_arn]
  dimensions = {
    ReplicationGroupId = aws_elasticache_replication_group.cache.replication_group_id
    Role               = "Primary"
  }
}

resource "aws_cloudwatch_metric_alarm" "cache_evictions" {
  alarm_name          = "${var.name}-cache-evictions"
  namespace           = "AWS/ElastiCache"
  metric_name         = "Evictions"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  treat_missing_data  = "breaching"
  alarm_actions       = [var.alarm_topic_arn]
  ok_actions          = [var.alarm_topic_arn]
  dimensions = {
    ReplicationGroupId = aws_elasticache_replication_group.cache.replication_group_id
    Role               = "Primary"
  }
}

resource "aws_db_parameter_group" "postgres" {
  name   = "${var.name}-postgres17"
  family = "postgres17"

  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }

  parameter {
    name         = "log_min_duration_statement"
    value        = "1000"
    apply_method = "immediate"
  }

  lifecycle { create_before_destroy = true }
}

data "aws_iam_policy_document" "rds_monitoring_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["monitoring.rds.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "rds_monitoring" {
  name               = "${var.name}-rds-monitoring"
  assume_role_policy = data.aws_iam_policy_document.rds_monitoring_assume.json
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

resource "aws_db_instance" "postgres" {
  identifier = var.name

  engine         = "postgres"
  engine_version = var.postgres_engine_version
  instance_class = var.db_instance_class
  db_name        = "logitrack"
  username       = "logitrack_admin"
  port           = 5432

  manage_master_user_password   = true
  master_user_secret_kms_key_id = aws_kms_key.database.arn

  allocated_storage     = 100
  max_allocated_storage = 500
  storage_type          = "gp3"
  storage_encrypted     = true
  kms_key_id            = aws_kms_key.database.arn

  multi_az               = true
  publicly_accessible    = false
  db_subnet_group_name   = aws_db_subnet_group.production.name
  vpc_security_group_ids = [aws_security_group.database.id]
  parameter_group_name   = aws_db_parameter_group.postgres.name

  backup_retention_period = 35
  backup_window           = "18:00-18:30"
  maintenance_window      = "sun:19:00-sun:19:30"
  copy_tags_to_snapshot   = true

  deletion_protection       = true
  skip_final_snapshot       = false
  final_snapshot_identifier = "${var.name}-final"

  auto_minor_version_upgrade            = true
  allow_major_version_upgrade           = false
  apply_immediately                     = false
  performance_insights_enabled          = true
  performance_insights_kms_key_id       = aws_kms_key.database.arn
  performance_insights_retention_period = 7
  enabled_cloudwatch_logs_exports       = ["postgresql", "upgrade"]
  monitoring_interval                   = 60
  monitoring_role_arn                   = aws_iam_role.rds_monitoring.arn

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_db_event_subscription" "postgres" {
  name      = "${var.name}-database-events"
  sns_topic = var.alarm_topic_arn

  source_type = "db-instance"
  source_ids  = [aws_db_instance.postgres.identifier]
  event_categories = [
    "availability",
    "backup",
    "failure",
    "failover",
    "low storage",
    "maintenance",
    "notification",
    "recovery",
  ]
}

resource "aws_cloudwatch_metric_alarm" "database_cpu_high" {
  alarm_name          = "${var.name}-database-cpu-high"
  namespace           = "AWS/RDS"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 5
  datapoints_to_alarm = 3
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = 80
  treat_missing_data  = "breaching"
  alarm_actions       = [var.alarm_topic_arn]
  ok_actions          = [var.alarm_topic_arn]
  dimensions          = { DBInstanceIdentifier = aws_db_instance.postgres.identifier }
}

resource "aws_cloudwatch_metric_alarm" "database_storage_low" {
  alarm_name          = "${var.name}-database-storage-low"
  namespace           = "AWS/RDS"
  metric_name         = "FreeStorageSpace"
  statistic           = "Minimum"
  period              = 300
  evaluation_periods  = 3
  datapoints_to_alarm = 3
  comparison_operator = "LessThanOrEqualToThreshold"
  threshold           = 21474836480
  treat_missing_data  = "breaching"
  alarm_actions       = [var.alarm_topic_arn]
  ok_actions          = [var.alarm_topic_arn]
  dimensions          = { DBInstanceIdentifier = aws_db_instance.postgres.identifier }
}
