locals {
  irsa_services = [
    "gateway",
    "auth",
    "converter",
    "notification",
    "worker"
  ]

  irsa_s3_bucket_arns = flatten([
    for bucket_name in values(module.s3.bucket_names) : [
      "arn:aws:s3:::${bucket_name}",
      "arn:aws:s3:::${bucket_name}/*"
    ]
  ])
}

resource "aws_iam_role" "irsa_roles" {

  for_each = toset(local.irsa_services)

  name = "${var.project_name}-${var.environment}-${each.key}-irsa-role"

  depends_on = [module.eks]

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Federated = module.eks.oidc_provider_arn
        }

        Action = "sts:AssumeRoleWithWebIdentity"

        Condition = {
          StringEquals = {
            "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub" = "system:serviceaccount:${var.kubernetes_namespace}:${each.key}-service-account"
          }
        }
      }
    ]

  })

  tags = {
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
  }
}

resource "aws_iam_policy" "irsa_s3_policy" {

  name = "${var.project_name}-${var.environment}-irsa-s3-policy"

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]

        Resource = local.irsa_s3_bucket_arns
      }
    ]

  })
}

resource "aws_iam_role_policy_attachment" "irsa_s3_attach" {

  for_each = aws_iam_role.irsa_roles

  role       = each.value.name
  policy_arn = aws_iam_policy.irsa_s3_policy.arn
}
