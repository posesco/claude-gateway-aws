# =============================================================================
# OBSERVABILIDAD PRIVADA EN ECS FARGATE (Grafana + Loki + Alertmanager)
# - Grafana 13.2.4 (Dashboard de Cuotas SQL + Inspector de Prompts en Loki)
# - Grafana Loki 3.7.9 (Almacenamiento e indexacion de Prompts y Eventos)
# - Prometheus Alertmanager 0.34.1 + AWS SNS (Alertas por email al >=80% de cuota)
# =============================================================================

# -----------------------------------------------------------------------------
# 1. Desacoplamiento de aws_security_group_rule (reglas 3000 y 3100 movidas inline
#    dentro de aws_security_group.ecs_tasks en main.tf para evitar conflicto)
# -----------------------------------------------------------------------------
removed {
  from = aws_security_group_rule.ecs_grafana_ingress_from_alb
  lifecycle {
    destroy = false
  }
}

removed {
  from = aws_security_group_rule.ecs_loki_ingress_self
  lifecycle {
    destroy = false
  }
}

removed {
  from = aws_security_group_rule.ecs_loki_egress_self
  lifecycle {
    destroy = false
  }
}

# -----------------------------------------------------------------------------
# 2. AWS Cloud Map (Service Discovery privado para loki.<project_name>.internal)
# -----------------------------------------------------------------------------
resource "aws_service_discovery_private_dns_namespace" "internal" {
  name        = "${var.project_name}.internal"
  description = "Namespace DNS privado para comunicacion interna Gateway to Loki en ECS"
  vpc         = var.vpc_id

  tags = {
    Name = "${var.project_name}-internal-dns"
  }
}

resource "aws_service_discovery_service" "loki" {
  name          = "loki"
  force_destroy = true

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.internal.id

    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    failure_threshold = 1
  }

  tags = {
    Name = "${var.project_name}-loki-discovery"
  }
}

# -----------------------------------------------------------------------------
# 3. AWS SNS Topic + Suscripcion de Email (var.alert_email) para Alertmanager
# -----------------------------------------------------------------------------
resource "aws_sns_topic" "quota_alerts" {
  name = "${var.project_name}-quota-alerts"

  tags = {
    Name = "${var.project_name}-quota-alerts"
  }
}

resource "aws_sns_topic_subscription" "quota_alerts_email" {
  topic_arn = aws_sns_topic.quota_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_iam_role_policy" "ecs_task_sns_alerts" {
  name = "${var.project_name}-sns-quota-alerts-policy"
  role = aws_iam_role.ecs_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AllowAlertmanagerPublishToQuotaSNS"
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = [aws_sns_topic.quota_alerts.arn]
      },
      {
        Sid      = "AllowGrafanaInitSyncDashboardsFromS3"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = [aws_s3_bucket.grafana_dashboards.arn]
      },
      {
        Sid      = "AllowGrafanaInitReadDashboardObjectsFromS3"
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = ["${aws_s3_bucket.grafana_dashboards.arn}/*"]
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# 4. Target Group y Listener Rule en el ALB Interno para var.observability_fqdn
# -----------------------------------------------------------------------------
resource "aws_lb_target_group" "grafana" {
  name                 = "${var.project_name}-grafana-tg"
  port                 = 3000
  protocol             = "HTTP"
  vpc_id               = var.vpc_id
  target_type          = "ip"
  deregistration_delay = 15

  health_check {
    enabled             = true
    path                = "/api/health"
    port                = "3000"
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    matcher             = "200"
  }

  tags = {
    Name = "${var.project_name}-grafana-tg"
  }
}

resource "aws_lb_listener_rule" "eyes_grafana" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.grafana.arn
  }

  condition {
    host_header {
      values = [var.observability_fqdn]
    }
  }

  tags = {
    Name = "${var.project_name}-eyes-grafana-rule"
  }
}

# -----------------------------------------------------------------------------
# 5. Secreto Admin Password de Grafana y Bucket S3 Privado para Dashboards JSON
# -----------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "grafana_admin_password" {
  name                    = "${var.project_name}/grafana-admin-password"
  description             = "Contrasena del administrador de Grafana en https://${var.observability_fqdn}"
  recovery_window_in_days = 0

  tags = {
    Name = "${var.project_name}-grafana-admin-password"
  }
}

resource "aws_secretsmanager_secret_version" "grafana_admin_password" {
  secret_id     = aws_secretsmanager_secret.grafana_admin_password.id
  secret_string = var.grafana_admin_password
}

resource "aws_s3_bucket" "grafana_dashboards" {
  bucket_prefix = "${var.project_name}-dashboards-"
  force_destroy = true

  tags = {
    Name = "${var.project_name}-grafana-dashboards"
  }
}

resource "aws_s3_bucket_public_access_block" "grafana_dashboards" {
  bucket = aws_s3_bucket.grafana_dashboards.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_object" "claude_gateway_dashboard" {
  bucket       = aws_s3_bucket.grafana_dashboards.id
  key          = "dashboards/claude-gateway-dashboard.json"
  source       = "${path.root}/monitoring/grafana/claude-gateway-dashboard.json"
  etag         = filemd5("${path.root}/monitoring/grafana/claude-gateway-dashboard.json")
  content_type = "application/json"

  tags = {
    Name = "${var.project_name}-claude-gateway-dashboard-json"
  }
}

# -----------------------------------------------------------------------------
# 5b. Configuraciones de Observabilidad en S3 (Alertmanager, Provisioning y Scripts)
# -----------------------------------------------------------------------------
resource "aws_s3_object" "alertmanager_config" {
  bucket = aws_s3_bucket.grafana_dashboards.id
  key    = "config/alertmanager/alertmanager.yml"
  content = templatefile("${path.root}/monitoring/alertmanager/alertmanager.yml.tftpl", {
    sns_topic_arn      = aws_sns_topic.quota_alerts.arn
    aws_region         = var.aws_region
    observability_fqdn = var.observability_fqdn
  })
  etag = md5(templatefile("${path.root}/monitoring/alertmanager/alertmanager.yml.tftpl", {
    sns_topic_arn      = aws_sns_topic.quota_alerts.arn
    aws_region         = var.aws_region
    observability_fqdn = var.observability_fqdn
  }))
  content_type = "text/yaml"

  tags = {
    Name = "${var.project_name}-alertmanager-config"
  }
}

resource "aws_s3_object" "grafana_provisioning" {
  for_each     = fileset("${path.root}/monitoring/grafana/provisioning", "**/*.yaml")
  bucket       = aws_s3_bucket.grafana_dashboards.id
  key          = "config/grafana/provisioning/${each.value}"
  source       = "${path.root}/monitoring/grafana/provisioning/${each.value}"
  etag         = filemd5("${path.root}/monitoring/grafana/provisioning/${each.value}")
  content_type = "text/yaml"

  tags = {
    Name = "${var.project_name}-grafana-provisioning-${replace(each.value, "/", "-")}"
  }
}

resource "aws_s3_object" "grafana_entrypoint" {
  bucket       = aws_s3_bucket.grafana_dashboards.id
  key          = "config/grafana/entrypoint.sh"
  source       = "${path.root}/monitoring/grafana/entrypoint.sh"
  etag         = filemd5("${path.root}/monitoring/grafana/entrypoint.sh")
  content_type = "application/x-sh"

  tags = {
    Name = "${var.project_name}-grafana-entrypoint"
  }
}

# -----------------------------------------------------------------------------
# 6. Task Definition y Servicio ECS Fargate (Grafana + Loki + Alertmanager)
# -----------------------------------------------------------------------------
locals {
  config_s3_etag = md5(join("", concat(
    [aws_s3_object.alertmanager_config.etag, aws_s3_object.grafana_entrypoint.etag],
    [for k in sort(keys(aws_s3_object.grafana_provisioning)) : aws_s3_object.grafana_provisioning[k].etag]
  )))
}

resource "aws_ecs_task_definition" "observability" {
  family                   = "${var.project_name}-observability"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  volume {
    name = "grafana-dashboards"
  }

  volume {
    name = "observability-config"
  }

  container_definitions = jsonencode([
    {
      name       = "dashboard-s3-sync"
      image      = "public.ecr.aws/aws-cli/aws-cli:latest"
      essential  = false
      entryPoint = ["/bin/sh", "-c"]
      command = [
        "aws s3 sync s3://${aws_s3_bucket.grafana_dashboards.id}/dashboards /dashboards --region ${var.aws_region} && aws s3 sync s3://${aws_s3_bucket.grafana_dashboards.id}/config /etc/observability --region ${var.aws_region} && chmod -R a+rX /dashboards /etc/observability"
      ]
      mountPoints = [
        {
          sourceVolume  = "grafana-dashboards"
          containerPath = "/dashboards"
          readOnly      = false
        },
        {
          sourceVolume  = "observability-config"
          containerPath = "/etc/observability"
          readOnly      = false
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.ecs.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "dashboard-s3-sync"
        }
      }
    },
    {
      name      = "loki"
      image     = "grafana/loki:3.7.9"
      essential = true
      command   = ["-config.file=/etc/loki/local-config.yaml"]
      portMappings = [
        {
          containerPort = 3100
          hostPort      = 3100
          protocol      = "tcp"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.ecs.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "loki"
        }
      }
    },
    {
      name      = "alertmanager"
      image     = "prom/alertmanager:v0.34.1"
      essential = true
      command = [
        "--config.file=/etc/observability/alertmanager/alertmanager.yml",
        "--storage.path=/tmp/alertmanager",
        "--web.listen-address=0.0.0.0:9093"
      ]
      dependsOn = [
        {
          containerName = "dashboard-s3-sync"
          condition     = "SUCCESS"
        }
      ]
      mountPoints = [
        {
          sourceVolume  = "observability-config"
          containerPath = "/etc/observability"
          readOnly      = true
        }
      ]
      environment = [
        {
          name  = "CONFIG_S3_ETAG"
          value = local.config_s3_etag
        }
      ]
      portMappings = [
        {
          containerPort = 9093
          hostPort      = 9093
          protocol      = "tcp"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.ecs.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "alertmanager"
        }
      }
    },
    {
      name       = "grafana"
      image      = "grafana/grafana:13.2.4"
      essential  = true
      entryPoint = ["/bin/sh", "/etc/observability/grafana/entrypoint.sh"]
      dependsOn = [
        {
          containerName = "dashboard-s3-sync"
          condition     = "SUCCESS"
        },
        {
          containerName = "loki"
          condition     = "START"
        },
        {
          containerName = "alertmanager"
          condition     = "START"
        }
      ]
      mountPoints = [
        {
          sourceVolume  = "grafana-dashboards"
          containerPath = "/var/lib/grafana/dashboards"
          readOnly      = true
        },
        {
          sourceVolume  = "observability-config"
          containerPath = "/etc/observability"
          readOnly      = true
        }
      ]
      portMappings = [
        {
          containerPort = 3000
          hostPort      = 3000
          protocol      = "tcp"
        }
      ]
      environment = [
        {
          name  = "GF_SERVER_ROOT_URL"
          value = "https://${var.observability_fqdn}"
        },
        {
          name  = "GF_SERVER_DOMAIN"
          value = var.observability_fqdn
        },
        {
          name  = "GF_SECURITY_ADMIN_USER"
          value = "admin"
        },
        {
          name  = "GF_USERS_ALLOW_SIGN_UP"
          value = "false"
        },
        {
          name  = "GF_UNIFIED_ALERTING_ENABLED"
          value = "true"
        },
        {
          name  = "GF_ALERTING_ENABLED"
          value = "false"
        },
        {
          name  = "GF_DASHBOARDS_DEFAULT_HOME_DASHBOARD_PATH"
          value = "/var/lib/grafana/dashboards/claude-gateway-dashboard.json"
        },
        {
          name  = "DASHBOARD_S3_ETAG"
          value = aws_s3_object.claude_gateway_dashboard.etag
        },
        {
          name  = "CONFIG_S3_ETAG"
          value = local.config_s3_etag
        }
      ]
      secrets = [
        {
          name      = "GF_SECURITY_ADMIN_PASSWORD"
          valueFrom = aws_secretsmanager_secret.grafana_admin_password.arn
        },
        {
          name      = "GATEWAY_POSTGRES_URL"
          valueFrom = var.postgres_url_secret_arn
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.ecs.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "grafana"
        }
      }
    }
  ])

  tags = {
    Name = "${var.project_name}-observability-taskdef"
  }
}

resource "aws_ecs_service" "observability" {
  name                              = "${var.project_name}-observability-service"
  cluster                           = aws_ecs_cluster.main.id
  task_definition                   = aws_ecs_task_definition.observability.arn
  launch_type                       = "FARGATE"
  desired_count                     = 1
  health_check_grace_period_seconds = 60

  network_configuration {
    subnets          = var.public_subnet_ids
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.grafana.arn
    container_name   = "grafana"
    container_port   = 3000
  }

  service_registries {
    registry_arn = aws_service_discovery_service.loki.arn
  }

  depends_on = [
    aws_lb_listener_rule.eyes_grafana
  ]

  tags = {
    Name = "${var.project_name}-observability-service"
  }
}
