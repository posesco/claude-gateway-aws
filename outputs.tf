# =============================================================================
# OUTPUTS PRINCIPALES DEL LABORATORIO CLAUDE APPS GATEWAY
# =============================================================================

output "cognito_issuer_url" {
  description = "URL del proveedor OIDC (Amazon Cognito User Pool) en la Cuenta A (Identidad)."
  value       = module.identity_cognito.issuer_url
}

output "tailscale_route_approval_note" {
  description = "Recordatorio critico para aprobar la ruta de subred privada en la consola de Tailscale."
  value       = <<-EOT
    ================================================================================
    ACCION REQUERIDA EN TAILSCALE ADMIN CONSOLE (https://login.tailscale.com/admin/machines):
    1. Localiza el nodo '${module.networking_dns.tailscale_router_instance_id}' (hostname: aws-claude-gateway-router).
    2. Haz clic en los tres puntos (...) -> 'Edit route settings'.
    3. Aprueba la ruta de subred anunciada: ${var.vpc_cidr}
    4. Asegurate de tener conectado el cliente Tailscale en tu portatil (--accept-routes).
    ================================================================================
  EOT
}

output "claude_login_instructions" {
  description = "Comando exacto e instrucciones para autenticar Claude Code CLI contra el Gateway privado."
  value       = <<-EOT
    ================================================================================
    INSTRUCCIONES DE CONEXION Y LOGIN EN CLAUDE CODE CLI:
    1. Edita ~/.claude/settings.json en tu portatil (elimina ANTHROPIC_BASE_URL si lo tenias):
       {
         "forceLoginMethod": "gateway",
         "forceLoginGatewayUrl": "https://${local.gateway_fqdn}"
       }

    2. Verifica en tu navegador o terminal que el Gateway responde por Tailscale:
       https://${local.gateway_fqdn}/readyz
       https://${local.gateway_fqdn}/.well-known/oauth-authorization-server

    3. Inicia sesion OIDC en Claude Code CLI ejecutando:
       claude
       (y dentro de la sesion escribe: /login)

    4. Credenciales de prueba aprovisionadas en Amazon Cognito (Cuenta A):
       - Perfil Senior (${format("%.2f", var.senior_monthly_limit_usd)} USD/mes - Grupo DevSenior):
         Usuario: ${var.senior_user_email}
       - Perfil Junior (${format("%.2f", var.junior_monthly_limit_usd)} USD/mes - Grupo DevJunior):
         Usuario: ${var.junior_user_email}
       - Administrador (Grupo claude-gateway-admins):
         Usuario: ${var.admin_user_email}
       (Contrasena inicial configurada en var.initial_user_password)
    ================================================================================
  EOT
}

output "workload_account_id" {
  description = "ID de la Cuenta B (Workload) donde residen la VPC, Tailscale, ALB Interno, ECS y RDS."
  value       = local.workload_account_id
}

output "cognito_client_id" {
  description = "Client ID de la aplicacion OIDC en Amazon Cognito (Cuenta A)."
  value       = module.identity_cognito.client_id
}

output "cognito_hosted_ui_url" {
  description = "URL del Hosted UI de Amazon Cognito en la Cuenta A."
  value       = module.identity_cognito.hosted_ui_url
}

output "gateway_primary_url" {
  description = "URL HTTPS principal del Claude Apps Gateway (accesible via Tailscale)."
  value       = "https://${local.gateway_fqdn}"
}

output "gateway_secondary_url" {
  description = "URL HTTPS secundaria (SAN) del Claude Apps Gateway (accesible via Tailscale)."
  value       = "https://${local.secondary_fqdn}"
}

output "internal_alb_dns_name" {
  description = "DNS privado del Application Load Balancer Interno en la Cuenta B."
  value       = module.gateway_ecs.internal_alb_dns_name
}

output "ecr_repository_url" {
  description = "URL del repositorio ECR en la Cuenta B donde subir la imagen del Claude Apps Gateway."
  value       = module.gateway_ecs.ecr_repository_url
}

output "rds_endpoint" {
  description = "Endpoint privado de la instancia RDS PostgreSQL 16 en la Cuenta B."
  value       = module.database.db_endpoint
}

output "tailscale_router_instance_id" {
  description = "ID de la instancia EC2 t4g.nano que actua como Tailscale Subnet Router en la Cuenta B."
  value       = module.networking_dns.tailscale_router_instance_id
}

output "cloudwatch_dashboard_url" {
  description = "URL directa para acceder al Dashboard de observabilidad de Claude Apps Gateway en la consola de AWS (Cuenta B)."
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards/dashboard/${module.gateway_ecs.cloudwatch_dashboard_name}"
}

output "grafana_eyes_url" {
  description = "URL privada HTTPS de Grafana + Loki + Alertmanager (accesible exclusivamente con Tailscale activo)."
  value       = "https://${local.observability_fqdn}"
}

output "alertmanager_sns_topic_arn" {
  description = "ARN del topico SNS en la Cuenta B para alertas por email (80% de cuota mensual) desde Alertmanager."
  value       = module.gateway_ecs.alertmanager_sns_topic_arn
}

output "grafana_dashboards_s3_bucket" {
  description = "Bucket S3 privado en la Cuenta B que almacena dashboards y configuracion de observabilidad y Gateway."
  value       = module.gateway_ecs.grafana_dashboards_s3_bucket
}
