# ==========================================================
# GITHUB ACTIONS OIDC (OPT-IN, ADDITIVE)
# ==========================================================
# All resources here are gated on var.enable_github_oidc (default false), so by
# default nothing is created and the existing static-access-key CI path is
# untouched. Enabling this ADDS a keyless auth option; it does not remove keys.
#
# To adopt: set enable_github_oidc = true, github_oidc_repo = "owner/repo",
# and github_oidc_policy_arns to the scoped deploy policy ARN(s). Then configure
# the GitHub Actions workflow to assume the role output below via
# aws-actions/configure-aws-credentials (role-to-assume).

locals {
  github_oidc_enabled = var.enable_github_oidc ? 1 : 0

  github_oidc_subjects = length(var.github_oidc_subject_claims) > 0 ? var.github_oidc_subject_claims : (
    var.github_oidc_repo != "" ? ["repo:${var.github_oidc_repo}:*"] : []
  )
}

resource "aws_iam_openid_connect_provider" "github" {
  count = local.github_oidc_enabled

  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-github-actions-oidc"
  })
}

resource "aws_iam_role" "github_actions" {
  count = local.github_oidc_enabled

  name = "${local.name_prefix}-github-actions-oidc-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Federated = aws_iam_openid_connect_provider.github[0].arn }
        Action    = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = local.github_oidc_subjects
          }
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-github-actions-oidc-role"
  })
}

resource "aws_iam_role_policy_attachment" "github_actions" {
  for_each = var.enable_github_oidc ? toset(var.github_oidc_policy_arns) : toset([])

  role       = aws_iam_role.github_actions[0].name
  policy_arn = each.value
}

output "github_actions_oidc_role_arn" {
  description = "ARN of the GitHub Actions OIDC role (null unless enable_github_oidc = true). Use as role-to-assume in CI."
  value       = try(aws_iam_role.github_actions[0].arn, null)
}
