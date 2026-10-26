resource "random_id" "idp_suffix" {
  byte_length = 4
}

# ==============================================================================
# Pre-Token Generation Lambda (Injects `groups` claim into OIDC tokens)
# ==============================================================================
data "archive_file" "pre_token_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda/pre_token_generation.py"
  output_path = "${path.module}/lambda/pre_token_generation.zip"
}

resource "aws_iam_role" "pre_token_lambda" {
  name = "${var.project_name}-cognito-pre-token-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "pre_token_lambda_basic" {
  role       = aws_iam_role.pre_token_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_cloudwatch_log_group" "pre_token_lambda" {
  name              = "/aws/lambda/${var.project_name}-cognito-pre-token"
  retention_in_days = 7
  skip_destroy      = false
}

resource "aws_lambda_function" "pre_token_generation" {
  function_name    = "${var.project_name}-cognito-pre-token"
  description      = "Injects Cognito User Pool groups into OIDC token claims for Claude Apps Gateway"
  role             = aws_iam_role.pre_token_lambda.arn
  filename         = data.archive_file.pre_token_zip.output_path
  source_code_hash = data.archive_file.pre_token_zip.output_base64sha256
  handler          = "pre_token_generation.handler"
  runtime          = var.lambda_runtime
  timeout          = 10

  depends_on = [
    aws_iam_role_policy_attachment.pre_token_lambda_basic,
    aws_cloudwatch_log_group.pre_token_lambda
  ]
}

# ==============================================================================
# Amazon Cognito User Pool & Hosted UI Domain
# ==============================================================================
resource "aws_cognito_user_pool" "main" {
  name                     = "${var.project_name}-user-pool"
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]
  deletion_protection      = "INACTIVE"

  password_policy {
    minimum_length                   = 12
    require_lowercase                = true
    require_numbers                  = true
    require_symbols                  = true
    require_uppercase                = true
    temporary_password_validity_days = 7
  }

  admin_create_user_config {
    allow_admin_create_user_only = true
  }

  lambda_config {
    pre_token_generation = aws_lambda_function.pre_token_generation.arn

    pre_token_generation_config {
      lambda_arn     = aws_lambda_function.pre_token_generation.arn
      lambda_version = "V1_0"
    }
  }
}

resource "aws_lambda_permission" "allow_cognito" {
  statement_id  = "AllowExecutionFromCognitoUserPool"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.pre_token_generation.function_name
  principal     = "cognito-idp.amazonaws.com"
  source_arn    = aws_cognito_user_pool.main.arn
}

resource "aws_cognito_user_pool_domain" "main" {
  domain       = "claude-idp-${random_id.idp_suffix.hex}"
  user_pool_id = aws_cognito_user_pool.main.id
}

# ==============================================================================
# Cognito User Groups (RBAC & Spend Quota Tiers)
# ==============================================================================
resource "aws_cognito_user_group" "admins" {
  name         = "claude-gateway-admins"
  user_pool_id = aws_cognito_user_pool.main.id
  description  = "Administradores del Claude Apps Gateway"
  precedence   = 1
}

resource "aws_cognito_user_group" "dev_senior" {
  name         = "DevSenior"
  user_pool_id = aws_cognito_user_pool.main.id
  description  = "Desarrollador Senior - Limite $10 USD/mes"
  precedence   = 10
}

resource "aws_cognito_user_group" "dev_junior" {
  name         = "DevJunior"
  user_pool_id = aws_cognito_user_pool.main.id
  description  = "Desarrollador Junior - Limite $5 USD/mes"
  precedence   = 20
}

# ==============================================================================
# Cognito Seeded Users & Group Memberships
# ==============================================================================
resource "aws_cognito_user" "admin" {
  user_pool_id   = aws_cognito_user_pool.main.id
  username       = var.admin_user_email
  password       = var.initial_user_password
  message_action = "SUPPRESS"
  enabled        = true

  attributes = {
    email          = var.admin_user_email
    email_verified = "true"
  }
}

resource "aws_cognito_user_in_group" "admin" {
  user_pool_id = aws_cognito_user_pool.main.id
  group_name   = aws_cognito_user_group.admins.name
  username     = aws_cognito_user.admin.username
}

resource "aws_cognito_user" "senior" {
  user_pool_id   = aws_cognito_user_pool.main.id
  username       = var.senior_user_email
  password       = var.initial_user_password
  message_action = "SUPPRESS"
  enabled        = true

  attributes = {
    email          = var.senior_user_email
    email_verified = "true"
  }
}

resource "aws_cognito_user_in_group" "senior" {
  user_pool_id = aws_cognito_user_pool.main.id
  group_name   = aws_cognito_user_group.dev_senior.name
  username     = aws_cognito_user.senior.username
}

resource "aws_cognito_user" "junior" {
  user_pool_id   = aws_cognito_user_pool.main.id
  username       = var.junior_user_email
  password       = var.initial_user_password
  message_action = "SUPPRESS"
  enabled        = true

  attributes = {
    email          = var.junior_user_email
    email_verified = "true"
  }
}

resource "aws_cognito_user_in_group" "junior" {
  user_pool_id = aws_cognito_user_pool.main.id
  group_name   = aws_cognito_user_group.dev_junior.name
  username     = aws_cognito_user.junior.username
}

resource "aws_cognito_user" "additional" {
  for_each = var.additional_users

  user_pool_id   = aws_cognito_user_pool.main.id
  username       = each.value.email
  password       = var.initial_user_password
  message_action = "SUPPRESS"
  enabled        = true

  attributes = {
    email          = each.value.email
    email_verified = "true"
  }
}

resource "aws_cognito_user_in_group" "additional" {
  for_each = var.additional_users

  user_pool_id = aws_cognito_user_pool.main.id
  group_name   = each.value.group
  username     = aws_cognito_user.additional[each.key].username

  depends_on = [
    aws_cognito_user_group.admins,
    aws_cognito_user_group.dev_senior,
    aws_cognito_user_group.dev_junior
  ]
}

# ==============================================================================
# OIDC App Client for Claude Apps Gateway
# ==============================================================================
resource "aws_cognito_user_pool_client" "gateway" {
  name                                 = "${var.project_name}-oidc-client"
  user_pool_id                         = aws_cognito_user_pool.main.id
  generate_secret                      = true
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["openid", "email", "profile"]
  supported_identity_providers         = ["COGNITO"]
  callback_urls                        = var.callback_urls
  logout_urls                          = var.logout_urls

  explicit_auth_flows = [
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_SRP_AUTH"
  ]
}
