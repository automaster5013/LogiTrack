data "aws_caller_identity" "current" {}
data "aws_subnet" "private" {
  count = 3
  id    = var.private_subnet_ids[count.index]
}
data "aws_ec2_managed_prefix_list" "cloudfront" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}

locals {
  public_cidrs = ["10.40.110.0/24", "10.40.120.0/24", "10.40.130.0/24"]
  secret_arns  = [var.database_secret_arn, var.cache_auth_secret_arn, var.kafka_scram_secret_arn]
}

resource "aws_internet_gateway" "edge" {
  vpc_id = var.vpc_id
  tags = {
    Name = "logitrack-production-edge"
  }
}
resource "aws_subnet" "public" {
  count                   = 3
  vpc_id                  = var.vpc_id
  availability_zone       = data.aws_subnet.private[count.index].availability_zone
  cidr_block              = local.public_cidrs[count.index]
  map_public_ip_on_launch = false
  tags = {
    Name = "logitrack-production-public-${count.index + 1}"
  }
}
resource "aws_route_table" "public" {
  vpc_id = var.vpc_id
  tags = {
    Name = "logitrack-production-public"
  }
}
resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.edge.id
}
resource "aws_route_table_association" "public" {
  count          = 3
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}
resource "aws_eip" "nat" {
  count      = 3
  domain     = "vpc"
  depends_on = [aws_internet_gateway.edge]
}
resource "aws_nat_gateway" "az" {
  count             = 3
  allocation_id     = aws_eip.nat[count.index].id
  subnet_id         = aws_subnet.public[count.index].id
  connectivity_type = "public"
}
resource "aws_route" "private_egress" {
  count                  = 3
  route_table_id         = var.private_route_table_ids[count.index]
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.az[count.index].id
}

resource "aws_security_group" "endpoints" {
  name   = "logitrack-production-endpoints"
  vpc_id = var.vpc_id
}
resource "aws_vpc_security_group_ingress_rule" "endpoints_from_app" {
  security_group_id            = aws_security_group.endpoints.id
  referenced_security_group_id = var.application_security_group_id
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
}
resource "aws_vpc_security_group_egress_rule" "app_to_endpoints" {
  security_group_id            = var.application_security_group_id
  referenced_security_group_id = aws_security_group.endpoints.id
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
}
resource "aws_vpc_endpoint" "interface" {
  for_each            = toset(["ecr.api", "ecr.dkr", "logs", "secretsmanager"])
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.${each.value}"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = var.private_subnet_ids
  security_group_ids  = [aws_security_group.endpoints.id]
}
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = var.private_route_table_ids
}

resource "aws_security_group" "alb" {
  name   = "logitrack-production-alb"
  vpc_id = var.vpc_id
}
resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  security_group_id = aws_security_group.alb.id
  prefix_list_id    = data.aws_ec2_managed_prefix_list.cloudfront.id
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}
resource "aws_vpc_security_group_egress_rule" "alb_to_web" {
  security_group_id            = aws_security_group.alb.id
  referenced_security_group_id = var.application_security_group_id
  from_port                    = 3000
  to_port                      = 3000
  ip_protocol                  = "tcp"
}
resource "aws_vpc_security_group_ingress_rule" "web_from_alb" {
  security_group_id            = var.application_security_group_id
  referenced_security_group_id = aws_security_group.alb.id
  from_port                    = 3000
  to_port                      = 3000
  ip_protocol                  = "tcp"
}
resource "aws_vpc_security_group_ingress_rule" "app_internal" {
  security_group_id            = var.application_security_group_id
  referenced_security_group_id = var.application_security_group_id
  from_port                    = 8080
  to_port                      = 8090
  ip_protocol                  = "tcp"
}
resource "aws_vpc_security_group_egress_rule" "app_internal" {
  security_group_id            = var.application_security_group_id
  referenced_security_group_id = var.application_security_group_id
  from_port                    = 8080
  to_port                      = 8090
  ip_protocol                  = "tcp"
}
resource "aws_vpc_security_group_egress_rule" "app_https" {
  security_group_id = var.application_security_group_id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  description       = "Cognito and contracted routing provider through per-AZ NAT"
}

resource "aws_lb" "edge" {
  name                       = "logitrack-production"
  internal                   = false
  load_balancer_type         = "application"
  security_groups            = [aws_security_group.alb.id]
  subnets                    = aws_subnet.public[*].id
  enable_deletion_protection = true
  drop_invalid_header_fields = true
}
resource "aws_lb_target_group" "web" {
  name                 = "logitrack-production-web"
  port                 = 3000
  protocol             = "HTTP"
  vpc_id               = var.vpc_id
  target_type          = "ip"
  deregistration_delay = 30
  health_check {
    path                = "/login"
    matcher             = "200-399"
    interval            = 15
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.edge.arn
  port              = 443
  protocol          = "HTTPS"
  certificate_arn   = var.certificate_arn
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}

resource "aws_service_discovery_private_dns_namespace" "production" {
  name = "production.logitrack.internal"
  vpc  = var.vpc_id
}
resource "aws_service_discovery_service" "api" {
  name = "api"
  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.production.id
    dns_records {
      ttl  = 10
      type = "A"
    }
    routing_policy = "MULTIVALUE"
  }
  health_check_custom_config {
  }
}

resource "aws_ecs_cluster" "production" {
  name = "logitrack-production"
  setting {
    name  = "containerInsights"
    value = "enhanced"
  }
}
resource "aws_cloudwatch_log_group" "api" {
  name              = "/ecs/logitrack-production/api"
  retention_in_days = 30
  lifecycle {
    prevent_destroy = true
  }
}
resource "aws_cloudwatch_log_group" "web" {
  name              = "/ecs/logitrack-production/web"
  retention_in_days = 30
  lifecycle {
    prevent_destroy = true
  }
}

data "aws_iam_policy_document" "task_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}
resource "aws_iam_role" "execution" {
  name               = "logitrack-production-ecs-execution"
  assume_role_policy = data.aws_iam_policy_document.task_assume.json
}
resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}
data "aws_iam_policy_document" "secrets" {
  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = local.secret_arns
  }
  statement {
    actions   = ["kms:Decrypt"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["secretsmanager.${var.aws_region}.amazonaws.com"]
    }
  }
}
resource "aws_iam_role_policy" "secrets" {
  role   = aws_iam_role.execution.id
  policy = data.aws_iam_policy_document.secrets.json
}
resource "aws_iam_role" "task" {
  name               = "logitrack-production-task"
  assume_role_policy = data.aws_iam_policy_document.task_assume.json
}

resource "aws_ecs_task_definition" "api" {
  family                   = "logitrack-production-api"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 2048
  memory                   = 4096
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn
  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }
  container_definitions = jsonencode([
    {
      name                   = "api"
      image                  = var.api_image
      essential              = true
      readonlyRootFilesystem = true
      user                   = "app"
      portMappings = [{
        containerPort = 8080
        protocol      = "tcp"
      }]
      linuxParameters = {
        initProcessEnabled = true
      },
      environment = [
        {
          name  = "DB_URL"
          value = "jdbc:postgresql://${var.database_endpoint}:5432/logitrack"
          }, {
          name  = "KAFKA_BOOTSTRAP"
          value = var.kafka_bootstrap_servers
        },
        {
          name  = "KAFKA_SECURITY_PROTOCOL"
          value = "SASL_SSL"
          }, {
          name  = "KAFKA_SASL_MECHANISM"
          value = "SCRAM-SHA-512"
          }, {
          name  = "KAFKA_TOPIC_REPLICATION_FACTOR"
          value = "3"
          }, {
          name  = "KAFKA_TOPIC_MIN_IN_SYNC_REPLICAS"
          value = "2"
          }, {
          name  = "REDIS_HOST"
          value = var.cache_endpoint
        },
        {
          name  = "REDIS_PORT"
          value = "6379"
          }, {
          name  = "REDIS_SSL_ENABLED"
          value = "true"
          }, {
          name  = "ANALYTICS_URL"
          value = "http://127.0.0.1:8090"
        },
        {
          name  = "SECURITY_ENABLED"
          value = "true"
          }, {
          name  = "SECURITY_CLIENT_ID"
          value = var.cognito_client_id
          }, {
          name  = "SPRING_SECURITY_OAUTH2_RESOURCESERVER_JWT_ISSUER_URI"
          value = var.cognito_issuer_uri
        },
        {
          name  = "CORS_ALLOWED_ORIGINS"
          value = var.public_origin
          }, {
          name  = "LOGITRACK_DEMO_SEED_ENABLED"
          value = "false"
          }, {
          name  = "LOGITRACK_REPORTS_WRITER_ENABLED"
          value = "true"
        }
      ],
      secrets = [
        {
          name      = "DB_USER"
          valueFrom = "${var.database_secret_arn}:username::"
          }, {
          name      = "DB_PASSWORD"
          valueFrom = "${var.database_secret_arn}:password::"
        },
        {
          name      = "REDIS_PASSWORD"
          valueFrom = "${var.cache_auth_secret_arn}:password::"
          }, {
          name      = "KAFKA_SASL_JAAS_CONFIG"
          valueFrom = "${var.kafka_scram_secret_arn}:jaas_config::"
        }
      ],
      healthCheck = {
        command     = ["CMD-SHELL", "wget -qO- http://127.0.0.1:8080/actuator/health/readiness | grep UP"]
        interval    = 15
        timeout     = 5
        retries     = 3
        startPeriod = 60
      },
      logConfiguration = {
        logDriver = "awslogs"
        options = { "awslogs-group" = aws_cloudwatch_log_group.api.name, "awslogs-region" = var.aws_region, "awslogs-stream-prefix" = "api"
        }
      }
    },
    {
      name                   = "analytics"
      image                  = var.analytics_image
      essential              = true
      readonlyRootFilesystem = true
      user                   = "appuser"
      portMappings = [{
        containerPort = 8090
        protocol      = "tcp"
      }],
      environment = [{
        name  = "ROUTING_PROVIDER"
        value = "osrm"
        }, {
        name  = "OSRM_BASE_URL"
        value = "https://router.project-osrm.org"
        }, {
        name  = "ROUTING_TIMEOUT_SECONDS"
        value = "2.5"
        }, {
        name  = "MAX_REQUEST_BODY_BYTES"
        value = "2097152"
      }],
      healthCheck = {
        command     = ["CMD", "python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8090/health')"]
        interval    = 15
        timeout     = 5
        retries     = 3
        startPeriod = 30
      },
      logConfiguration = {
        logDriver = "awslogs"
        options = { "awslogs-group" = aws_cloudwatch_log_group.api.name, "awslogs-region" = var.aws_region, "awslogs-stream-prefix" = "analytics"
        }
      }
    }
  ])
}

resource "aws_ecs_task_definition" "web" {
  family                   = "logitrack-production-web"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 1024
  memory                   = 2048
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn
  container_definitions = jsonencode([{
    name                   = "web"
    image                  = var.web_image
    essential              = true
    readonlyRootFilesystem = true
    user                   = "node"
    portMappings = [{
      containerPort = 3000
      protocol      = "tcp"
    }],
    environment = [{
      name  = "HOSTNAME"
      value = "0.0.0.0"
      }, {
      name  = "AUTH_REQUIRED"
      value = "true"
      }, {
      name  = "INTERNAL_API_URL"
      value = "http://api.production.logitrack.internal:8080"
      }, {
      name  = "COGNITO_AUTHORIZATION_BASE_URL"
      value = var.cognito_authorization_base_url
      }, {
      name  = "COGNITO_ISSUER_URI"
      value = var.cognito_issuer_uri
      }, {
      name  = "COGNITO_CLIENT_ID"
      value = var.cognito_client_id
      }, {
      name  = "OIDC_REDIRECT_URI"
      value = "${var.public_origin}/auth/callback"
      }, {
      name  = "OIDC_POST_LOGOUT_REDIRECT_URI"
      value = "${var.public_origin}/login"
    }],
    healthCheck = {
      command     = ["CMD", "node", "-e", "fetch('http://127.0.0.1:3000/login').then(r=>{if(!r.ok)process.exit(1)}).catch(()=>process.exit(1))"]
      interval    = 15
      timeout     = 5
      retries     = 3
      startPeriod = 30
    },
    logConfiguration = {
      logDriver = "awslogs"
      options = { "awslogs-group" = aws_cloudwatch_log_group.web.name, "awslogs-region" = var.aws_region, "awslogs-stream-prefix" = "web"
      }
    }
  }])
}

resource "aws_ecs_service" "api" {
  name                               = "api"
  cluster                            = aws_ecs_cluster.production.id
  task_definition                    = aws_ecs_task_definition.api.arn
  desired_count                      = 3
  launch_type                        = "FARGATE"
  platform_version                   = "1.4.0"
  enable_execute_command             = false
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200
  health_check_grace_period_seconds  = 90
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }
  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.application_security_group_id]
    assign_public_ip = false
  }
  service_registries {
    registry_arn = aws_service_discovery_service.api.arn
  }
}
resource "aws_ecs_service" "web" {
  name                               = "web"
  cluster                            = aws_ecs_cluster.production.id
  task_definition                    = aws_ecs_task_definition.web.arn
  desired_count                      = 3
  launch_type                        = "FARGATE"
  platform_version                   = "1.4.0"
  enable_execute_command             = false
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200
  health_check_grace_period_seconds  = 60
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }
  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.application_security_group_id]
    assign_public_ip = false
  }
  load_balancer {
    target_group_arn = aws_lb_target_group.web.arn
    container_name   = "web"
    container_port   = 3000
  }
  depends_on = [aws_lb_listener.https]
}

resource "aws_appautoscaling_target" "api" {
  max_capacity       = 12
  min_capacity       = 3
  resource_id        = "service/${aws_ecs_cluster.production.name}/${aws_ecs_service.api.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}
resource "aws_appautoscaling_policy" "api_cpu" {
  name               = "api-cpu"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.api.resource_id
  scalable_dimension = aws_appautoscaling_target.api.scalable_dimension
  service_namespace  = aws_appautoscaling_target.api.service_namespace
  target_tracking_scaling_policy_configuration {
    target_value       = 60
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
  }
}
resource "aws_appautoscaling_target" "web" {
  max_capacity       = 12
  min_capacity       = 3
  resource_id        = "service/${aws_ecs_cluster.production.name}/${aws_ecs_service.web.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}
resource "aws_appautoscaling_policy" "web_cpu" {
  name               = "web-cpu"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.web.resource_id
  scalable_dimension = aws_appautoscaling_target.web.scalable_dimension
  service_namespace  = aws_appautoscaling_target.web.service_namespace
  target_tracking_scaling_policy_configuration {
    target_value       = 60
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "alb_unhealthy" {
  alarm_name          = "logitrack-production-web-unhealthy"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "UnHealthyHostCount"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  treat_missing_data  = "breaching"
  alarm_actions       = [var.alarm_topic_arn]
  ok_actions          = [var.alarm_topic_arn]
  dimensions = {
    TargetGroup  = aws_lb_target_group.web.arn_suffix
    LoadBalancer = aws_lb.edge.arn_suffix
  }
}
