output "ecr_repository_url" {
  description = "URL del repositorio ECR en la Cuenta B para subir la imagen del Claude Apps Gateway"
  value       = aws_ecr_repository.gateway.repository_url
}

output "ecs_cluster_name" {
  description = "Nombre del cluster ECS Fargate en la Cuenta B"
  value       = aws_ecs_cluster.main.name
}

output "ecs_service_name" {
  description = "Nombre del servicio ECS Fargate del Gateway"
  value       = aws_ecs_service.gateway.name
}

output "ecs_tasks_security_group_id" {
  description = "ID del Security Group de las tareas ECS Fargate (usado por RDS para permitir 5432)"
  value       = aws_security_group.ecs_tasks.id
}

output "internal_alb_dns_name" {
  description = "DNS name privado del Application Load Balancer Interno (destino de los CNAMEs en Cloudflare)"
  value       = aws_lb.internal.dns_name
}

output "internal_alb_arn" {
  description = "ARN del Application Load Balancer Interno"
  value       = aws_lb.internal.arn
}

output "internal_alb_security_group_id" {
  description = "ID del Security Group del ALB Interno"
  value       = aws_security_group.internal_alb.id
}

output "gateway_config_ssm_parameter_name" {
  description = "Nombre del parametro SSM que contiene el archivo gateway.yaml renderizado"
  value       = aws_ssm_parameter.gateway_config.name
}

output "seed_quotas_ssm_parameter_name" {
  description = "Nombre del parametro SSM que contiene el script SQL de inicializacion de topes mensuales"
  value       = aws_ssm_parameter.seed_quotas_sql.name
}

output "cloudwatch_dashboard_name" {
  description = "Nombre del CloudWatch Dashboard creado en la Cuenta B"
  value       = aws_cloudwatch_dashboard.gateway.dashboard_name
}

output "alertmanager_sns_topic_arn" {
  description = "ARN del topico SNS en la Cuenta B para alertas por email (80% de cuota mensual) desde Alertmanager"
  value       = aws_sns_topic.quota_alerts.arn
}

output "observability_ecs_service_name" {
  description = "Nombre del servicio ECS Fargate de observabilidad (Grafana + Loki + Alertmanager)"
  value       = aws_ecs_service.observability.name
}

output "grafana_dashboards_s3_bucket" {
  description = "Nombre del bucket S3 privado en la Cuenta B que almacena los dashboards JSON de Grafana"
  value       = aws_s3_bucket.grafana_dashboards.id
}
