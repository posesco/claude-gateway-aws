# =============================================================================
# MODULO 05: CLAUDE APPS GATEWAY (ECR, ALB INTERNO, ECS FARGATE, BEDROCK IAM,
#            S3 Y SEED AUTOMATICO DE CUOTAS EN POSTGRESQL)
# =============================================================================

# -----------------------------------------------------------------------------
# 1. Repositorio ECR con force_delete = true para destruccion limpia
# -----------------------------------------------------------------------------
resource "aws_ecr_repository" "gateway" {
  name                 = "${var.project_name}-gateway"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = "${var.project_name}-gateway-ecr"
  }
}

resource "aws_ecr_lifecycle_policy" "gateway" {
  repository = aws_ecr_repository.gateway.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Mantener solo las ultimas 5 imagenes en el laboratorio"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 5
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# 1b. Construccion y Push Automatico de la Imagen Oficial a ECR (Cuenta B)
#     Empaqueta el binario oficial `claude` (con `claude gateway`) y el bundle
#     CA de RDS PostgreSQL desde docker/Dockerfile antes de arrancar ECS.
# -----------------------------------------------------------------------------
resource "null_resource" "build_and_push_gateway_image" {
  count = var.auto_build_gateway_image && var.gateway_image_uri == "" ? 1 : 0

  triggers = {
    dockerfile_sha256  = filesha256("${path.root}/docker/Dockerfile")
    entrypoint_sha256  = filesha256("${path.root}/docker/entrypoint.sh")
    sha256_proxy       = filesha256("${path.root}/docker/gateway_proxy_loki.py")
    script_sha256      = filesha256("${path.root}/scripts/build_and_push_gateway.sh")
    ecr_repository_url = aws_ecr_repository.gateway.repository_url
    claude_version     = var.claude_binary_version
  }

  provisioner "local-exec" {
    command = "bash \"${path.root}/scripts/build_and_push_gateway.sh\""

    environment = {
      AWS_REGION          = var.aws_region
      ECR_REPOSITORY_URL  = aws_ecr_repository.gateway.repository_url
      WORKLOAD_ACCOUNT_ID = var.workload_account_id
      ASSUME_ROLE_ARN     = var.workload_assume_role_arn
      IMAGE_TAG           = "latest"
      CLAUDE_VERSION      = var.claude_binary_version
      DOCKER_CONTEXT_DIR  = "${path.root}/docker"
    }
  }

  depends_on = [aws_ecr_repository.gateway]
}

# -----------------------------------------------------------------------------
# 2. Secretos en AWS Secrets Manager (recovery_window_in_days = 0)
# -----------------------------------------------------------------------------
resource "random_password" "jwt_secret" {
  length  = 48
  special = false
}

resource "random_password" "admin_write_key" {
  length  = 48
  special = false
}

resource "aws_secretsmanager_secret" "oidc_client_secret" {
  name                    = "${var.project_name}/oidc-client-secret"
  description             = "Client Secret OIDC de Amazon Cognito (Cuenta A) para el Claude Apps Gateway"
  recovery_window_in_days = 0

  tags = {
    Name = "${var.project_name}-oidc-client-secret"
  }
}

resource "aws_secretsmanager_secret_version" "oidc_client_secret" {
  secret_id     = aws_secretsmanager_secret.oidc_client_secret.id
  secret_string = var.cognito_client_secret
}

resource "aws_secretsmanager_secret" "jwt_secret" {
  name                    = "${var.project_name}/gateway-jwt-secret"
  description             = "Clave de firma JWT para sesiones internas del Claude Apps Gateway"
  recovery_window_in_days = 0

  tags = {
    Name = "${var.project_name}-gateway-jwt-secret"
  }
}

resource "aws_secretsmanager_secret_version" "jwt_secret" {
  secret_id     = aws_secretsmanager_secret.jwt_secret.id
  secret_string = random_password.jwt_secret.result
}

resource "aws_secretsmanager_secret" "admin_write_key" {
  name                    = "${var.project_name}/gateway-admin-write-key"
  description             = "Admin API Write Key del Claude Apps Gateway para operaciones administrativas"
  recovery_window_in_days = 0

  tags = {
    Name = "${var.project_name}-gateway-admin-write-key"
  }
}

resource "aws_secretsmanager_secret_version" "admin_write_key" {
  secret_id     = aws_secretsmanager_secret.admin_write_key.id
  secret_string = random_password.admin_write_key.result
}

# -----------------------------------------------------------------------------
# 3. Configuracion del Gateway y seed SQL en el bucket privado compartido
# -----------------------------------------------------------------------------
locals {
  gateway_config = templatefile("${path.root}/config/gateway.yaml.tftpl", {
    gateway_fqdn             = var.gateway_fqdn
    private_subnet_cidrs     = var.private_subnet_cidrs
    cognito_issuer_url       = var.cognito_issuer_url
    cognito_client_id        = var.cognito_client_id
    admin_group              = var.admin_group_name
    aws_region               = var.aws_region
    senior_monthly_limit_usd = var.senior_monthly_limit_usd
    junior_monthly_limit_usd = var.junior_monthly_limit_usd
    senior_group             = var.senior_group_name
    junior_group             = var.junior_group_name
  })
  seed_quotas_sql = templatefile("${path.root}/config/seed_quotas.sql.tftpl", {
    senior_group               = var.senior_group_name
    junior_group               = var.junior_group_name
    admin_group                = var.admin_group_name
    senior_monthly_limit_usd   = var.senior_monthly_limit_usd
    junior_monthly_limit_usd   = var.junior_monthly_limit_usd
    senior_monthly_limit_cents = floor(var.senior_monthly_limit_usd * 100)
    junior_monthly_limit_cents = floor(var.junior_monthly_limit_usd * 100)
  })
}

resource "aws_s3_object" "gateway_config" {
  bucket                 = aws_s3_bucket.grafana_dashboards.id
  key                    = "gateway/gateway.yaml"
  content                = local.gateway_config
  etag                   = md5(local.gateway_config)
  content_type           = "text/yaml"
  server_side_encryption = "AES256"
  tags = {
    Name = "${var.project_name}-gateway-yaml"
  }
}

resource "aws_s3_object" "seed_quotas_sql" {
  bucket                 = aws_s3_bucket.grafana_dashboards.id
  key                    = "gateway/seed_quotas.sql"
  content                = local.seed_quotas_sql
  etag                   = md5(local.seed_quotas_sql)
  content_type           = "text/plain"
  server_side_encryption = "AES256"
  tags = {
    Name = "${var.project_name}-seed-quotas-sql"
  }
}

# -----------------------------------------------------------------------------
# 4. Security Groups (ALB Interno y Tareas ECS Fargate sin NAT Gateway)
# -----------------------------------------------------------------------------
resource "aws_security_group" "internal_alb" {
  name        = "${var.project_name}-internal-alb-sg"
  description = "Security Group para el ALB Interno (HTTPS 443 exclusivo desde Tailscale Subnet Router y VPC)"
  vpc_id      = var.vpc_id

  ingress {
    description     = "HTTPS 443 desde el Tailscale Subnet Router"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [var.tailscale_router_security_group_id]
  }

  ingress {
    description = "HTTPS 443 desde el rango interno de la VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "Trafico hacia las tareas ECS Fargate en el puerto 8080"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-internal-alb-sg"
  }
}

resource "aws_security_group" "ecs_tasks" {
  name        = "${var.project_name}-ecs-tasks-sg"
  description = "Security Group para tareas ECS Fargate (Ingreso exclusivo desde ALB Interno en 8080; salida HTTPS y PostgreSQL)"
  vpc_id      = var.vpc_id

  # Cero trafico entrante desde Internet a pesar de assign_public_ip = true
  ingress {
    description     = "HTTP 8080 exclusivo desde el ALB Interno"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.internal_alb.id]
  }

  ingress {
    description     = "HTTP 3000 (Grafana) exclusivo desde el ALB Interno (eyes)"
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.internal_alb.id]
  }

  ingress {
    description = "HTTP 3100 (Loki) entre tareas ECS Fargate del cluster (Gateway to Loki)"
    from_port   = 3100
    to_port     = 3100
    protocol    = "tcp"
    self        = true
  }

  egress {
    description = "Salida HTTPS (443) hacia Amazon Bedrock, Cognito OIDC (Cuenta A), ECR, S3, SNS y Secrets Manager"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Salida PostgreSQL (5432) hacia RDS en subredes privadas de la VPC"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "Salida HTTP 3100 hacia Loki dentro del mismo Security Group de tareas ECS"
    from_port   = 3100
    to_port     = 3100
    protocol    = "tcp"
    self        = true
  }

  tags = {
    Name = "${var.project_name}-ecs-tasks-sg"
  }
}

# -----------------------------------------------------------------------------
# 5. Internal Application Load Balancer (ALB Interno en Subredes Privadas)
# -----------------------------------------------------------------------------
resource "aws_lb" "internal" {
  name               = "${var.project_name}-internal-alb"
  internal           = true
  load_balancer_type = "application"
  subnets            = var.private_subnet_ids
  security_groups    = [aws_security_group.internal_alb.id]

  # Requerido para respuestas en streaming prolongadas de Claude en Bedrock
  idle_timeout = 3600

  tags = {
    Name = "${var.project_name}-internal-alb"
  }
}

resource "aws_lb_target_group" "gateway" {
  name                 = "${var.project_name}-gateway-tg"
  port                 = 8080
  protocol             = "HTTP"
  vpc_id               = var.vpc_id
  target_type          = "ip"
  deregistration_delay = 15

  health_check {
    enabled             = true
    path                = "/readyz"
    port                = "8080"
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    matcher             = "200"
  }

  tags = {
    Name = "${var.project_name}-gateway-tg"
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.internal.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.acm_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.gateway.arn
  }
}

# -----------------------------------------------------------------------------
# 6. Roles IAM para ECS (Execution Role + Task Role con permisos Amazon Bedrock)
# -----------------------------------------------------------------------------
data "aws_iam_policy_document" "ecs_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_execution" {
  name               = "${var.project_name}-ecs-execution-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role.json
}

resource "aws_iam_role_policy_attachment" "ecs_execution_standard" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "ecs_execution_secrets" {
  name = "${var.project_name}-ecs-execution-secrets"
  role = aws_iam_role.ecs_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadSecretsManager"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = [
          var.postgres_url_secret_arn,
          aws_secretsmanager_secret.oidc_client_secret.arn,
          aws_secretsmanager_secret.jwt_secret.arn,
          aws_secretsmanager_secret.admin_write_key.arn,
          aws_secretsmanager_secret.grafana_admin_password.arn
        ]
      },
      {
        Sid      = "DecryptKMSForSecrets"
        Effect   = "Allow"
        Action   = ["kms:Decrypt"]
        Resource = ["*"]
      }
    ]
  })
}

resource "aws_iam_role" "ecs_task" {
  name               = "${var.project_name}-ecs-task-bedrock-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role.json
}

resource "aws_iam_role_policy" "ecs_task_bedrock" {
  name = "${var.project_name}-bedrock-invoke-policy"
  role = aws_iam_role.ecs_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "InvokeClaudeModelsAndInferenceProfiles"
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream",
          "bedrock:CountTokens"
        ]
        Resource = [
          "arn:aws:bedrock:*::foundation-model/anthropic.claude-*",
          "arn:aws:bedrock:*:*:inference-profile/eu.anthropic.claude-*"
        ]
      },
      {
        Sid    = "AllowBedrockMarketplaceAutoSubscription"
        Effect = "Allow"
        Action = [
          "aws-marketplace:ViewSubscriptions",
          "aws-marketplace:Subscribe",
          "aws-marketplace:Unsubscribe"
        ]
        Resource = ["*"]
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# 7. CloudWatch Logs, Cluster ECS, Task Definition (initContainer + Gateway) y Servicio
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/${var.project_name}"
  retention_in_days = 7
  skip_destroy      = false

  tags = {
    Name = "${var.project_name}-ecs-logs"
  }
}

resource "aws_ecs_cluster" "main" {
  name = "${var.project_name}-cluster"

  setting {
    name  = "containerInsights"
    value = "disabled"
  }

  tags = {
    Name = "${var.project_name}-cluster"
  }
}

locals {
  effective_gateway_image = var.gateway_image_uri != "" ? var.gateway_image_uri : "${aws_ecr_repository.gateway.repository_url}:latest"
}

resource "aws_ecs_task_definition" "gateway" {
  family                   = "${var.project_name}-gateway"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  volume {
    name = "gateway-config"
  }

  container_definitions = jsonencode([
    {
      name       = "gateway-config-sync"
      image      = "public.ecr.aws/aws-cli/aws-cli:latest"
      essential  = false
      entryPoint = ["/bin/sh", "-c"]
      command = [
        "aws s3 cp s3://${aws_s3_bucket.grafana_dashboards.id}/${aws_s3_object.gateway_config.key} /gateway-config/gateway.yaml --region ${var.aws_region} --only-show-errors && aws s3 cp s3://${aws_s3_bucket.grafana_dashboards.id}/${aws_s3_object.seed_quotas_sql.key} /gateway-config/seed_quotas.sql --region ${var.aws_region} --only-show-errors && chmod -R a+rX /gateway-config && test -s /gateway-config/gateway.yaml && test -s /gateway-config/seed_quotas.sql"
      ]
      mountPoints = [
        {
          sourceVolume  = "gateway-config"
          containerPath = "/gateway-config"
          readOnly      = false
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.ecs.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "gateway-config-sync"
        }
      }
    },
    {
      name       = "db-quota-seeder"
      image      = "public.ecr.aws/docker/library/postgres:16-alpine"
      essential  = false
      entryPoint = ["/bin/sh", "-c"]
      command = [
        "echo 'Ejecutando seed idempotente de topes mensuales ($10 DevSenior / $5 DevJunior) en RDS PostgreSQL...' && psql \"$GATEWAY_POSTGRES_URL\" -v ON_ERROR_STOP=1 -f /gateway-config/seed_quotas.sql && echo 'Topes inicializados correctamente.'"
      ]
      dependsOn = [
        {
          containerName = "gateway-config-sync"
          condition     = "SUCCESS"
        }
      ]
      mountPoints = [
        {
          sourceVolume  = "gateway-config"
          containerPath = "/gateway-config"
          readOnly      = true
        }
      ]
      secrets = [
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
          awslogs-stream-prefix = "db-seeder"
        }
      }
    },
    {
      name      = "claude-gateway"
      image     = local.effective_gateway_image
      essential = true
      dependsOn = [
        {
          containerName = "db-quota-seeder"
          condition     = "SUCCESS"
        }
      ]
      mountPoints = [
        {
          sourceVolume  = "gateway-config"
          containerPath = "/gateway-config"
          readOnly      = true
        }
      ]
      portMappings = [
        {
          containerPort = 8080
          hostPort      = 8080
          protocol      = "tcp"
        }
      ]
      environment = [
        {
          name  = "AWS_REGION"
          value = var.aws_region
        },
        {
          name  = "CLAUDE_CONFIG_DIR"
          value = "/tmp/.claude"
        },
        {
          name  = "LOKI_PUSH_URL"
          value = "http://loki.${var.project_name}.internal:3100/loki/api/v1/push"
        },
        {
          name  = "PROXY_SCRIPT_SHA256"
          value = filesha256("${path.root}/docker/gateway_proxy_loki.py")
        },
        {
          name  = "GATEWAY_CONFIG_SHA256"
          value = sha256(local.gateway_config)
        },
        {
          name  = "SEED_QUOTAS_SHA256"
          value = sha256(local.seed_quotas_sql)
        }
      ]
      secrets = [
        {
          name      = "GATEWAY_POSTGRES_URL"
          valueFrom = var.postgres_url_secret_arn
        },
        {
          name      = "OIDC_CLIENT_SECRET"
          valueFrom = aws_secretsmanager_secret.oidc_client_secret.arn
        },
        {
          name      = "GATEWAY_JWT_SECRET"
          valueFrom = aws_secretsmanager_secret.jwt_secret.arn
        },
        {
          name      = "GATEWAY_ADMIN_WRITE_KEY"
          valueFrom = aws_secretsmanager_secret.admin_write_key.arn
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.ecs.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "gateway"
        }
      }
    }
  ])

  tags = {
    Name = "${var.project_name}-gateway-taskdef"
  }

  depends_on = [aws_iam_role_policy.ecs_task_sns_alerts]
}

resource "aws_ecs_service" "gateway" {
  name                              = "${var.project_name}-service"
  cluster                           = aws_ecs_cluster.main.id
  task_definition                   = aws_ecs_task_definition.gateway.arn
  launch_type                       = "FARGATE"
  desired_count                     = 1
  force_new_deployment              = true
  health_check_grace_period_seconds = 60

  network_configuration {
    subnets          = var.public_subnet_ids
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.gateway.arn
    container_name   = "claude-gateway"
    container_port   = 8080
  }

  depends_on = [
    aws_lb_listener.https,
    null_resource.build_and_push_gateway_image
  ]

  tags = {
    Name = "${var.project_name}-ecs-service"
  }
}
