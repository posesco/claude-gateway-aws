locals {
  workload_account_id = var.create_workload_account ? module.organization.workload_account_id : var.existing_workload_account_id
  gateway_fqdn        = "${var.primary_subdomain}.${var.domain_name}"
  secondary_fqdn      = "${var.secondary_subdomain}.${var.domain_name}"

  common_tags = {
    Project      = var.project_name
    Environment  = var.environment
    ManagedBy    = "Terraform"
    Architecture = "MultiAccount-Tailscale-ZeroNAT"
  }
}

# -----------------------------------------------------------------------------
# Provider AWS - Cuenta A (Identidad: AWS Organizations + Amazon Cognito + S3 State)
# -----------------------------------------------------------------------------
provider "aws" {
  alias  = "identity"
  region = var.aws_region

  default_tags {
    tags = merge(local.common_tags, {
      AccountRole = "Identity-Account-A"
    })
  }
}

# Provider AWS por defecto apuntando a Identidad para llamadas sin alias explicito
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = merge(local.common_tags, {
      AccountRole = "Identity-Account-A"
    })
  }
}

# -----------------------------------------------------------------------------
# Provider AWS - Cuenta B (Workload: VPC, Tailscale, ALB Interno, ECS, RDS, Bedrock)
# -----------------------------------------------------------------------------
provider "aws" {
  alias  = "workload"
  region = var.aws_region

  assume_role {
    role_arn     = "arn:aws:iam::${local.workload_account_id}:role/${var.organization_access_role_name}"
    session_name = "TerraformClaudeGatewayWorkload"
  }

  default_tags {
    tags = merge(local.common_tags, {
      AccountRole = "Workload-Account-B"
    })
  }
}

# -----------------------------------------------------------------------------
# Provider Cloudflare (Validacion DNS de ACM + CNAMEs hacia el ALB Interno)
# -----------------------------------------------------------------------------
provider "cloudflare" {
  api_token = var.cloudflare_api_token
}
