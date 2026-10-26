output "workload_account_id" {
  description = "The 12-digit AWS Account ID of the Workload account."
  value       = var.create_workload_account ? aws_organizations_account.workload[0].id : var.existing_workload_account_id
}

output "workload_account_arn" {
  description = "The ARN of the Workload account (if created via AWS Organizations)."
  value       = var.create_workload_account ? aws_organizations_account.workload[0].arn : null
}

output "organization_access_role_arn" {
  description = "Cross-account IAM role ARN used by Terraform to provision resources in the Workload account."
  value       = "arn:aws:iam::${var.create_workload_account ? aws_organizations_account.workload[0].id : var.existing_workload_account_id}:role/${var.organization_access_role_name}"
}
