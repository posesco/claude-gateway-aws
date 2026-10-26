# =============================================================================
# CLAUDE APPS GATEWAY LAB — ORQUESTACION MULTI-CUENTA (CUENTA A + CUENTA B)
# =============================================================================

locals {
  observability_fqdn = "${var.observability_subdomain}.${var.domain_name}"
}

# -----------------------------------------------------------------------------
# 1. Modulo 01: AWS Organizations (Creacion / Vinculacion de Cuenta B Workload)
# -----------------------------------------------------------------------------
module "organization" {
  source = "./modules/01-organization"

  providers = {
    aws = aws.identity
  }

  create_workload_account       = var.create_workload_account
  existing_workload_account_id  = var.existing_workload_account_id
  workload_account_email        = var.workload_account_email
  workload_account_name         = var.workload_account_name
  organization_access_role_name = var.organization_access_role_name
  close_on_deletion             = var.close_on_deletion
}

# -----------------------------------------------------------------------------
# 2. Modulo 02: Identidad OIDC en Amazon Cognito (Cuenta A - eu-west-1)
#    Incluye grupos (DevSenior, DevJunior, claude-gateway-admins), usuarios y
#    Lambda Pre-Token Generation para inyectar el claim 'groups' en el ID Token.
# -----------------------------------------------------------------------------
module "identity_cognito" {
  source = "./modules/02-identity-cognito"

  providers = {
    aws = aws.identity
  }

  project_name = var.project_name
  aws_region   = var.aws_region
  domain_name  = var.domain_name

  callback_urls = [
    "https://${local.gateway_fqdn}/oauth/callback",
    "https://${local.secondary_fqdn}/oauth/callback",
    "http://localhost:8080/oauth/callback"
  ]

  logout_urls = [
    "https://${local.gateway_fqdn}",
    "https://${local.secondary_fqdn}",
    "http://localhost:8080"
  ]

  initial_user_password = var.initial_user_password
  admin_user_email      = var.admin_user_email
  senior_user_email     = var.senior_user_email
  junior_user_email     = var.junior_user_email
  additional_users      = var.additional_cognito_users
  lambda_runtime        = var.cognito_lambda_runtime
}

# -----------------------------------------------------------------------------
# 3. Modulo 03: Red Privada (Cero NAT), ACM TLS, Cloudflare DNS y Tailscale
#    Desplegado en la Cuenta B (Workload) asumiendo OrganizationAccountAccessRole
# -----------------------------------------------------------------------------
module "networking_dns" {
  source = "./modules/03-networking-dns"

  providers = {
    aws        = aws.workload
    cloudflare = cloudflare
  }

  project_name               = var.project_name
  vpc_cidr                   = var.vpc_cidr
  public_subnet_cidrs        = var.public_subnet_cidrs
  private_subnet_cidrs       = var.private_subnet_cidrs
  domain_name                = var.domain_name
  primary_subdomain          = var.primary_subdomain
  secondary_subdomain        = var.secondary_subdomain
  observability_subdomain    = var.observability_subdomain
  cloudflare_zone_id         = var.cloudflare_zone_id
  tailscale_auth_key         = var.tailscale_auth_key
  internal_alb_dns_name      = module.gateway_ecs.internal_alb_dns_name
  create_gateway_dns_records = true
}

# -----------------------------------------------------------------------------
# 4. Modulo 04: Base de Datos RDS PostgreSQL 16 (db.t4g.micro en Cuenta B)
#    Configurada con skip_final_snapshot = true y recovery_window_in_days = 0
# -----------------------------------------------------------------------------
module "database" {
  source = "./modules/04-database"

  providers = {
    aws = aws.workload
  }

  project_name                       = var.project_name
  vpc_id                             = module.networking_dns.vpc_id
  private_subnet_ids                 = module.networking_dns.private_subnet_ids
  ecs_tasks_security_group_id        = module.gateway_ecs.ecs_tasks_security_group_id
  tailscale_router_security_group_id = module.networking_dns.tailscale_router_security_group_id
  db_name                            = var.db_name
  db_username                        = var.db_username
}

# -----------------------------------------------------------------------------
# 5. Modulo 05: Claude Apps Gateway en ECS Fargate, ALB Interno, IAM Bedrock y
#    Seed Automatico de Topes Mensuales ($10 DevSenior / $5 DevJunior)
# -----------------------------------------------------------------------------
module "gateway_ecs" {
  source = "./modules/05-gateway-ecs"

  providers = {
    aws = aws.workload
  }

  project_name                       = var.project_name
  aws_region                         = var.aws_region
  vpc_id                             = module.networking_dns.vpc_id
  vpc_cidr                           = module.networking_dns.vpc_cidr
  public_subnet_ids                  = module.networking_dns.public_subnet_ids
  private_subnet_ids                 = module.networking_dns.private_subnet_ids
  private_subnet_cidrs               = module.networking_dns.private_subnet_cidrs
  tailscale_router_security_group_id = module.networking_dns.tailscale_router_security_group_id
  acm_certificate_arn                = module.networking_dns.acm_certificate_arn
  gateway_fqdn                       = local.gateway_fqdn
  observability_fqdn                 = local.observability_fqdn
  alert_email                        = var.alert_email
  grafana_admin_password             = var.grafana_admin_password
  cognito_issuer_url                 = module.identity_cognito.issuer_url
  cognito_client_id                  = module.identity_cognito.client_id
  cognito_client_secret              = module.identity_cognito.client_secret
  admin_group_name                   = module.identity_cognito.admin_group_name
  senior_group_name                  = module.identity_cognito.senior_group_name
  junior_group_name                  = module.identity_cognito.junior_group_name
  senior_monthly_limit_usd           = var.senior_monthly_limit_usd
  junior_monthly_limit_usd           = var.junior_monthly_limit_usd
  postgres_url_secret_arn            = module.database.postgres_url_secret_arn
  gateway_image_uri                  = var.gateway_image_uri
  workload_account_id                = local.workload_account_id
  workload_assume_role_arn           = module.organization.organization_access_role_arn
  auto_build_gateway_image           = var.auto_build_gateway_image
  claude_binary_version              = var.claude_binary_version
}
