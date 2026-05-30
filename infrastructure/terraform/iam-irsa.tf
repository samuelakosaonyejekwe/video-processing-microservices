locals {
  irsa_services = [
    "gateway",
    "auth",
    "converter",
    "notification",
    "worker"
  ]
}

resource "aws_iam_role" "irsa_roles" {

  for_each = toset(local.irsa_services)

  name = "${var.project_name}-${var.environment}-${each.key}-irsa-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Federated = aws_iam_openid_connect_provider.eks.arn
        }

        Action = "sts:AssumeRoleWithWebIdentity"

        Condition = {
          StringEquals = {
            "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub" = "system:serviceaccount:${var.kubernetes_namespace}:${each.key}-service-account"
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

        Resource = [
          "arn:aws:s3:::${var.s3_bucket_name}",
          "arn:aws:s3:::${var.s3_bucket_name}/*"
        ]
      }
    ]

  })
}

resource "aws_iam_role_policy_attachment" "irsa_s3_attach" {

  for_each = aws_iam_role.irsa_roles

  role       = each.value.name
  policy_arn = aws_iam_policy.irsa_s3_policy.arn
}
