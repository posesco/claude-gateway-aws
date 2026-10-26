variable "project_name" {
  description = "Nombre base del proyecto para etiquetado y recursos de red"
  type        = string
}

variable "vpc_cidr" {
  description = "Bloque CIDR principal de la VPC en la Cuenta B (Workload)"
  type        = string
  default     = "10.20.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "Lista de CIDRs para las 2 subredes publicas en distintas AZs"
  type        = list(string)
  default     = ["10.20.1.0/24", "10.20.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "Lista de CIDRs para las 2 subredes privadas aisladas en distintas AZs"
  type        = list(string)
  default     = ["10.20.11.0/24", "10.20.12.0/24"]
}

variable "domain_name" {
  description = "Dominio base gestionado en Cloudflare"
  type        = string
  default     = "midominio.com"
}

variable "primary_subdomain" {
  description = "Subdominio principal para el Gateway (ej. aidevtool)"
  type        = string
  default     = "aidevtool"
}

variable "secondary_subdomain" {
  description = "Subdominio secundario SAN para el Gateway (ej. dev)"
  type        = string
  default     = "dev"
}

variable "observability_subdomain" {
  description = "Subdominio privado en Cloudflare para Grafana + Loki + Alertmanager (ej. eyes)"
  type        = string
  default     = "eyes"
}

variable "cloudflare_zone_id" {
  description = "Zone ID de Cloudflare para el dominio base"
  type        = string
}

variable "tailscale_auth_key" {
  description = "Auth Key efimera/reusable de Tailscale para registrar el Subnet Router automaticamente"
  type        = string
  sensitive   = true
}

variable "tailscale_hostname" {
  description = "Hostname del nodo Subnet Router en la red Tailscale"
  type        = string
  default     = "aws-claude-gateway-router"
}

variable "tailscale_instance_type" {
  description = "Tipo de instancia EC2 ARM64 para el Tailscale Subnet Router (t4g.micro = 1 GB RAM)"
  type        = string
  default     = "t4g.micro"
}

variable "internal_alb_dns_name" {
  description = "DNS name del ALB interno en la Cuenta B para apuntar los CNAME de Cloudflare"
  type        = string
  default     = ""
}

variable "create_gateway_dns_records" {
  description = "Si es true, crea los registros CNAME de acceso privado en Cloudflare apuntando al ALB Interno"
  type        = bool
  default     = true
}

