# =============================================================================
# MODULO 04: BASE DE DATOS RDS POSTGRESQL (CUENTA B - WORKLOAD)
# =============================================================================

# Password alfanumerico URL-safe para que las cadenas postgres://user:pass@host:5432/db
# nunca rompan el parser URI del contenedor del Gateway ni de psql.
resource "random_password" "db_password" {
  length  = 24
  special = false
}

resource "aws_db_subnet_group" "main" {
  name        = "${var.project_name}-db-subnet-group"
  description = "Grupo de subredes privadas aisladas para RDS PostgreSQL"
  subnet_ids  = var.private_subnet_ids

  tags = {
    Name = "${var.project_name}-db-subnet-group"
  }
}

resource "aws_security_group" "rds" {
  name        = "${var.project_name}-rds-sg"
  description = "Permite trafico PostgreSQL (5432) unicamente desde ECS Fargate y Tailscale Router"
  vpc_id      = var.vpc_id

  ingress {
    description     = "PostgreSQL desde tareas ECS Fargate del Gateway y seeder"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [var.ecs_tasks_security_group_id, var.tailscale_router_security_group_id]
  }

  egress {
    description = "Salida permitida"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-rds-sg"
  }
}

resource "aws_db_instance" "postgres" {
  identifier                 = "${var.project_name}-postgres"
  engine                     = "postgres"
  engine_version             = var.db_engine_version
  auto_minor_version_upgrade = true
  instance_class             = var.db_instance_class
  allocated_storage          = 20
  storage_type               = "gp3"
  storage_encrypted          = true

  db_name  = var.db_name
  username = var.db_username
  password = random_password.db_password.result

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false
  multi_az               = false

  # Configuracion optimizada para laboratorio y destruccion limpia (terraform destroy)
  backup_retention_period = 0
  skip_final_snapshot     = true
  deletion_protection     = false
  apply_immediately       = true

  tags = {
    Name = "${var.project_name}-postgres"
  }
}

# -----------------------------------------------------------------------------
# AWS Secrets Manager: Cadena de conexion PostgreSQL (recovery_window_in_days = 0)
# -----------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "postgres_url" {
  name_prefix             = "${var.project_name}-postgres-url-"
  description             = "Cadena de conexion PostgreSQL para Claude Apps Gateway"
  recovery_window_in_days = 0

  tags = {
    Name = "${var.project_name}-postgres-url"
  }
}

resource "aws_secretsmanager_secret_version" "postgres_url" {
  secret_id     = aws_secretsmanager_secret.postgres_url.id
  secret_string = "postgres://${var.db_username}:${random_password.db_password.result}@${aws_db_instance.postgres.address}:${aws_db_instance.postgres.port}/${var.db_name}?sslmode=require"
}
