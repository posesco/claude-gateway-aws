variable "project_name" {
  description = "Nombre base del proyecto para etiquetado y recursos de base de datos"
  type        = string
}

variable "vpc_id" {
  description = "ID de la VPC en la Cuenta B (Workload)"
  type        = string
}

variable "private_subnet_ids" {
  description = "Lista de IDs de subredes privadas aisladas para el DB Subnet Group"
  type        = list(string)
}

variable "ecs_tasks_security_group_id" {
  description = "ID del Security Group de las tareas ECS Fargate autorizadas a conectar al puerto 5432"
  type        = string
}

variable "tailscale_router_security_group_id" {
  description = "ID del Security Group del Tailscale Subnet Router para administracion privada opcional"
  type        = string
}

variable "db_name" {
  description = "Nombre de la base de datos PostgreSQL para el Gateway"
  type        = string
  default     = "claudegateway"
}

variable "db_username" {
  description = "Usuario maestro de la instancia RDS PostgreSQL"
  type        = string
  default     = "gwadmin"
}

variable "db_instance_class" {
  description = "Clase de instancia RDS (db.t4g.micro por defecto para laboratorio)"
  type        = string
  default     = "db.t4g.micro"
}

variable "db_engine_version" {
  description = "Version del motor PostgreSQL en RDS"
  type        = string
  default     = "16"
}
