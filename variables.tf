variable "aws_region" {
  description = "Region principal de AWS para desplegar Cognito (Cuenta A) y el Gateway con Bedrock (Cuenta B)."
  type        = string
  default     = "eu-west-1"
}

variable "project_name" {
  description = "Prefijo identificador para todos los recursos del laboratorio."
  type        = string
  default     = "claude-gateway-lab"
}

variable "environment" {
  description = "Entorno de despliegue (lab, dev, prod)."
  type        = string
  default     = "lab"
}

variable "domain_name" {
  description = "Dominio base gestionado en Cloudflare."
  type        = string
}

variable "primary_subdomain" {
  description = "Subdominio principal para el Claude Apps Gateway."
  type        = string
}

variable "secondary_subdomain" {
  description = "Subdominio secundario (SAN) para el Claude Apps Gateway."
  type        = string
}

variable "cloudflare_zone_id" {
  description = "Zone ID de Cloudflare correspondiente al dominio principal."
  type        = string
}

variable "cloudflare_api_token" {
  description = "API Token de Cloudflare con permisos DNS:Edit en la zona. Si es null, el provider leera la variable de entorno CLOUDFLARE_API_TOKEN."
  type        = string
  default     = null
  sensitive   = true
}

variable "tailscale_auth_key" {
  description = "Auth Key (reusable/ephemeral o pre-autorizada) de Tailscale para registrar el Subnet Router de la Cuenta B."
  type        = string
  sensitive   = true
}

variable "create_workload_account" {
  description = "Si es true, crea la Cuenta B (workload) mediante AWS Organizations en la Cuenta A. Si ya existe, pon false e indica existing_workload_account_id."
  type        = bool
  default     = false
}

variable "existing_workload_account_id" {
  description = "ID de la Cuenta B (12 digitos) cuando create_workload_account = false."
  type        = string
  default     = ""
}

variable "workload_account_email" {
  description = "Correo electronico unico para la Cuenta B en AWS Organizations (ej. aws-workload@midominio.com)."
  type        = string
}

variable "workload_account_name" {
  description = "Nombre descriptivo de la Cuenta B en AWS Organizations."
  type        = string
  default     = "claude-gateway-workload"
}

variable "close_on_deletion" {
  description = "Si es true, intenta cerrar la cuenta miembro de AWS Organizations en terraform destroy. Recomendado false para preservar la cuenta."
  type        = bool
  default     = false
}

variable "organization_access_role_name" {
  description = "Nombre del rol IAM en la Cuenta B que asumira Terraform desde la Cuenta A."
  type        = string
  default     = "OrganizationAccountAccessRole"
}

variable "initial_user_password" {
  description = "Contrasena inicial permanente asignada a los usuarios creados en Cognito."
  type        = string
  sensitive   = true
}

variable "admin_user_email" {
  description = "Email del usuario administrador del Gateway en Cognito (grupo claude-gateway-admins)."
  type        = string
}

variable "senior_user_email" {
  description = "Email del usuario Desarrollador Senior en Cognito (grupo DevSenior - $10/mes)."
  type        = string
}

variable "junior_user_email" {
  description = "Email del usuario Desarrollador Junior en Cognito (grupo DevJunior - $5/mes)."
  type        = string
}

variable "additional_cognito_users" {
  description = "Mapa opcional de usuarios adicionales a crear en Cognito con su email y grupo asignado."
  type = map(object({
    email = string
    group = string
  }))
  default = {}
}

variable "cognito_lambda_runtime" {
  description = "Runtime de AWS Lambda para el trigger Pre-Token Generation de Cognito."
  type        = string
  default     = "python3.14"
}

variable "vpc_cidr" {
  description = "Bloque CIDR privado para la VPC de la Cuenta B anunciada por Tailscale."
  type        = string
  default     = "10.20.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDRs de las 2 subredes publicas en la Cuenta B (Tailscale Router y salida de tareas ECS Fargate sin NAT Gateway)."
  type        = list(string)
  default     = ["10.20.1.0/24", "10.20.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDRs de las 2 subredes privadas aisladas en la Cuenta B (ALB Interno y RDS PostgreSQL)."
  type        = list(string)
  default     = ["10.20.11.0/24", "10.20.12.0/24"]
}

variable "db_name" {
  description = "Nombre de la base de datos PostgreSQL para el Claude Apps Gateway."
  type        = string

}

variable "db_username" {
  description = "Usuario maestro de RDS PostgreSQL."
  type        = string
}

variable "senior_monthly_limit_usd" {
  description = "Tope de gasto mensual en USD para el grupo DevSenior."
  type        = number
  default     = 10.00
}

variable "junior_monthly_limit_usd" {
  description = "Tope de gasto mensual en USD para el grupo DevJunior."
  type        = number
  default     = 5.00
}

variable "gateway_image_uri" {
  description = "URI opcional de la imagen Docker del Claude Apps Gateway. Si es vacia, se usa el repositorio ECR creado en la Cuenta B (<ecr_repo_url>:latest)."
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

variable "observability_subdomain" {
  description = "Subdominio privado en Cloudflare para acceder a Grafana via Tailscale (ej. eyes)."
  type        = string
  default     = "eyes"
}

variable "alert_email" {
  description = "Correo electronico destino en Alertmanager/SNS para alertas cuando un usuario alcance el 80% de su cuota mensual."
  type        = string
}

variable "grafana_admin_password" {
  description = "Contrasena del usuario admin de Grafana en la URL privada de observabilidad."
  type        = string
  sensitive   = true
}
