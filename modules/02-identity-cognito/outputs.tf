output "user_pool_id" {
  description = "The ID of the Cognito User Pool."
  value       = aws_cognito_user_pool.main.id
}

output "user_pool_arn" {
  description = "The ARN of the Cognito User Pool."
  value       = aws_cognito_user_pool.main.arn
}

output "issuer_url" {
  description = "The OIDC Issuer URL of the Cognito User Pool."
  value       = "https://cognito-idp.${var.aws_region}.amazonaws.com/${aws_cognito_user_pool.main.id}"
}

output "hosted_ui_url" {
  description = "The Hosted UI base URL for the Cognito User Pool."
  value       = "https://${aws_cognito_user_pool_domain.main.domain}.auth.${var.aws_region}.amazoncognito.com"
}

output "client_id" {
  description = "The OIDC App Client ID for the Claude Apps Gateway."
  value       = aws_cognito_user_pool_client.gateway.id
}

output "client_secret" {
  description = "The OIDC App Client Secret for the Claude Apps Gateway."
  value       = aws_cognito_user_pool_client.gateway.client_secret
  sensitive   = true
}

output "admin_group_name" {
  description = "Name of the Cognito group for gateway administrators."
  value       = aws_cognito_user_group.admins.name
}

output "senior_group_name" {
  description = "Name of the Cognito group for Senior Developers ($10/month quota)."
  value       = aws_cognito_user_group.dev_senior.name
}

output "junior_group_name" {
  description = "Name of the Cognito group for Junior Developers ($5/month quota)."
  value       = aws_cognito_user_group.dev_junior.name
}

output "provisioned_users" {
  description = "Summary of provisioned Cognito users and their assigned groups."
  value = merge(
    {
      admin  = { email = aws_cognito_user.admin.username, group = aws_cognito_user_group.admins.name }
      senior = { email = aws_cognito_user.senior.username, group = aws_cognito_user_group.dev_senior.name }
      junior = { email = aws_cognito_user.junior.username, group = aws_cognito_user_group.dev_junior.name }
    },
    {
      for k, u in var.additional_users : k => {
        email = u.email
        group = u.group
      }
    }
  )
}
