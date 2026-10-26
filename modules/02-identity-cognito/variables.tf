variable "project_name" {
  description = "Project name prefix used for naming Cognito and IAM resources."
  type        = string
}

variable "aws_region" {
  description = "AWS region where the Cognito User Pool is deployed."
  type        = string
  default     = "eu-west-1"
}

variable "domain_name" {
  description = "Primary domain name for user email addresses and lab URLs."
  type        = string
  default     = "midominio.com"
}

variable "callback_urls" {
  description = "Allowed OIDC OAuth 2.0 callback URLs for the Claude Apps Gateway."
  type        = list(string)
  default = [
    "https://aidevtool.midominio.com/oauth/callback",
    "https://dev.midominio.com/oauth/callback",
    "http://localhost:8080/oauth/callback"
  ]
}

variable "logout_urls" {
  description = "Allowed OIDC OAuth 2.0 sign-out URLs for the Claude Apps Gateway."
  type        = list(string)
  default = [
    "https://aidevtool.midominio.com",
    "https://dev.midominio.com",
    "http://localhost:8080"
  ]
}

variable "initial_user_password" {
  description = "Initial password assigned to seeded Cognito lab users."
  type        = string
  sensitive   = true
}

variable "admin_user_email" {
  description = "Email for the platform administrator user in claude-gateway-admins."
  type        = string
  default     = "admin@midominio.com"
}

variable "senior_user_email" {
  description = "Email for the senior developer user in DevSenior ($10/month quota)."
  type        = string
  default     = "senior@midominio.com"
}

variable "junior_user_email" {
  description = "Email for the junior developer user in DevJunior ($5/month quota)."
  type        = string
  default     = "junior@midominio.com"
}

variable "additional_users" {
  description = "Additional Cognito users to create and assign to groups (map of key => { email, group })."
  type = map(object({
    email = string
    group = string
  }))
  default = {}
}

variable "lambda_runtime" {
  description = "AWS Lambda Python runtime version for the Pre-Token Generation trigger."
  type        = string
  default     = "python3.14"
}
