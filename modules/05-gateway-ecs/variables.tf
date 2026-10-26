variable "project_name" {
  description = "Nombre base del proyecto para etiquetado y recursos de ECS, ALB e IAM"
  type        = string
}

variable "aws_region" {
  description = "Region de AWS donde se despliega ECS Fargate y se invoca Amazon Bedrock"
  type        = string
  default     = "eu-west-1"
}

variable "vpc_id" {
  description = "ID de la VPC en la Cuenta B (Workload)"
  type        = string
}

variable "vpc_cidr" {
  description = "Bloque CIDR de la VPC en la Cuenta B"
  type        = string
}

variable "public_subnet_ids" {
  description = "IDs de las subredes publicas para tareas ECS Fargate con assign_public_ip = true (Cero NAT Gateway)"
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "IDs de las subredes privadas aisladas para el ALB Interno"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "Bloques CIDR de las subredes privadas para trusted_proxies en gateway.yaml"
  type        = list(string)
}

variable "tailscale_router_security_group_id" {
  description = "ID del Security Group del Tailscale Subnet Router autorizado a llegar al puerto 443 del ALB Interno"
  type        = string
}

variable "acm_certificate_arn" {
  description = "ARN del certificado ACM validado en Cloudflare para subdominios principal y secundario"
  type        = string
}

variable "gateway_fqdn" {
  description = "FQDN principal del Claude Apps Gateway (ej. aidevtool.midominio.com)"
  type        = string
}

variable "observability_fqdn" {
  description = "FQDN privado en Cloudflare para acceder a Grafana via Tailscale (ej. eyes.midominio.com)"
  type        = string
}

variable "alert_email" {
  description = "Correo electronico destino en Alertmanager/SNS para alertas cuando un usuario alcance el 80% de su cuota mensual"
  type        = string
  default     = "alertas@midominio.com"
}

variable "grafana_admin_password" {
  description = "Contrasena del usuario admin de Grafana en la URL privada de observabilidad"
  type        = string
  sensitive   = true
}

variable "cognito_issuer_url" {
  description = "URL del emisor OIDC del User Pool de Amazon Cognito en la Cuenta A"
  type        = string
}

variable "cognito_client_id" {
  description = "Client ID de la aplicacion OIDC en Amazon Cognito (Cuenta A)"
  type        = string
}

variable "cognito_client_secret" {
  description = "Client Secret de la aplicacion OIDC en Amazon Cognito (Cuenta A)"
  type        = string
  sensitive   = true
}

variable "admin_group_name" {
  description = "Nombre del grupo OIDC de administradores del Gateway"
  type        = string
  default     = "claude-gateway-admins"
}

variable "senior_group_name" {
  description = "Nombre del grupo OIDC para desarrolladores Senior ($10/mes)"
  type        = string
  default     = "DevSenior"
}

variable "junior_group_name" {
  description = "Nombre del grupo OIDC para desarrolladores Junior ($5/mes)"
  type        = string
  default     = "DevJunior"
}

variable "senior_monthly_limit_usd" {
  description = "Tope de gasto mensual en USD para el grupo DevSenior"
  type        = number
  default     = 10.00
}

variable "junior_monthly_limit_usd" {
  description = "Tope de gasto mensual en USD para el grupo DevJunior"
  type        = number
  default     = 5.00
}

variable "postgres_url_secret_arn" {
  description = "ARN del secreto en Secrets Manager que almacena la URL de conexion a RDS PostgreSQL"
  type        = string
}

variable "gateway_image_uri" {
  description = "URI opcional de la imagen del contenedor del Claude Apps Gateway. Si es vacia, usa el ECR creado en este modulo"
  type        = string
  default     = ""
}

variable "workload_account_id" {
  description = "ID de 12 digitos de la Cuenta B (Workload) donde reside el repositorio ECR"
  type        = string
}

variable "workload_assume_role_arn" {
  description = "ARN del rol IAM en la Cuenta B que asume el script local de construccion Docker para autenticarse en ECR"
  type        = string
  default     = ""
}

variable "auto_build_gateway_image" {
  description = "Si es true, construye y sube automaticamente la imagen Docker del Claude Apps Gateway a ECR en la Cuenta B durante terraform apply usando docker/Dockerfile."
  type        = bool
  default     = true
}

variable "claude_binary_version" {
  description = "Version del binario oficial de Claude Code a empaquetar en la imagen Docker del Gateway (ej. 'latest' o '2.1.296')."
  type        = string
  default     = "latest"
}
