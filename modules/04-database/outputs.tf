output "db_instance_id" {
  description = "Identificador de la instancia RDS PostgreSQL"
  value       = aws_db_instance.postgres.id
}

output "db_endpoint" {
  description = "Endpoint de conexion (host:port) de RDS PostgreSQL"
  value       = aws_db_instance.postgres.endpoint
}

output "db_address" {
  description = "Hostname DNS privado de la instancia RDS PostgreSQL"
  value       = aws_db_instance.postgres.address
}

output "db_port" {
  description = "Puerto de la instancia RDS PostgreSQL"
  value       = aws_db_instance.postgres.port
}

output "db_name" {
  description = "Nombre de la base de datos creada"
  value       = aws_db_instance.postgres.db_name
}

output "rds_security_group_id" {
  description = "ID del Security Group de RDS PostgreSQL"
  value       = aws_security_group.rds.id
}

output "postgres_url_secret_arn" {
  description = "ARN del secreto en Secrets Manager con la URL de conexion PostgreSQL"
  value       = aws_secretsmanager_secret.postgres_url.arn
}

output "postgres_connection_url" {
  description = "Cadena de conexion completa PostgreSQL para el Gateway y el contenedor de seed"
  value       = aws_secretsmanager_secret_version.postgres_url.secret_string
  sensitive   = true
}
