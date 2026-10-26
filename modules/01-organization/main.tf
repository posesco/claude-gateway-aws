data "aws_organizations_organization" "current" {
  count = var.create_workload_account ? 1 : 0
}

resource "aws_organizations_account" "workload" {
  count                      = var.create_workload_account ? 1 : 0
  name                       = var.workload_account_name
  email                      = var.workload_account_email
  role_name                  = var.organization_access_role_name
  iam_user_access_to_billing = "ALLOW"
  close_on_deletion          = var.close_on_deletion
}
