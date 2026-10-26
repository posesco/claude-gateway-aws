variable "create_workload_account" {
  description = "Whether to create a new AWS Organizations member account for the Workload environment. Set to false if reusing an existing member account."
  type        = bool
  default     = true
}

variable "existing_workload_account_id" {
  description = "Existing AWS Account ID for the Workload environment when create_workload_account = false."
  type        = string
  default     = ""
}

variable "workload_account_email" {
  description = "Unique root email address for the Workload AWS member account (e.g., aws-workload@midominio.com)."
  type        = string
}

variable "workload_account_name" {
  description = "Friendly name for the Workload AWS member account."
  type        = string
  default     = "claude-gateway-workload"
}

variable "organization_access_role_name" {
  description = "IAM role name created in the member account for cross-account administration from the Management account."
  type        = string
  default     = "OrganizationAccountAccessRole"
}

variable "close_on_deletion" {
  description = "Whether to close the AWS member account on terraform destroy."
  type        = bool
  default     = false
}
