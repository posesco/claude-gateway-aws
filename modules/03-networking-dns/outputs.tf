output "vpc_id" {
  description = "ID de la VPC en la Cuenta B (Workload)"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "Bloque CIDR de la VPC"
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_ids" {
  description = "IDs de las 2 subredes publicas"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs de las 2 subredes privadas aisladas"
  value       = aws_subnet.private[*].id
}

output "private_subnet_cidrs" {
  description = "Bloques CIDR de las subredes privadas aisladas"
  value       = aws_subnet.private[*].cidr_block
}

output "acm_certificate_arn" {
  description = "ARN del certificado ACM validado para subdominios principal y secundario"
  value       = aws_acm_certificate_validation.gateway.certificate_arn
}

output "tailscale_router_instance_id" {
  description = "ID de la instancia EC2 del Tailscale Subnet Router"
  value       = aws_instance.tailscale_router.id
}

output "tailscale_router_private_ip" {
  description = "IP privada del Tailscale Subnet Router"
  value       = aws_instance.tailscale_router.private_ip
}

output "tailscale_router_public_ip" {
  description = "IP publica de salida del Tailscale Subnet Router"
  value       = aws_instance.tailscale_router.public_ip
}

output "tailscale_router_security_group_id" {
  description = "ID del Security Group del Tailscale Subnet Router"
  value       = aws_security_group.tailscale_router.id
}

output "gateway_primary_fqdn" {
  description = "FQDN principal del Gateway"
  value       = "${var.primary_subdomain}.${var.domain_name}"
}

output "gateway_secondary_fqdn" {
  description = "FQDN secundario (SAN) del Gateway"
  value       = "${var.secondary_subdomain}.${var.domain_name}"
}

output "observability_fqdn" {
  description = "FQDN privado de Grafana + Loki + Alertmanager (eyes)"
  value       = "${var.observability_subdomain}.${var.domain_name}"
}
