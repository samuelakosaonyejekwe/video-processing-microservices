locals {
  irsa_services = [
    "gateway",
    "auth",
    "converter",
    "notification",
    "worker"
  ]

  # OIDC issuer host (without scheme) used for the IRSA trust-policy conditions.
  oidc_issuer_host = replace(module.eks.cluster_oidc_issuer_url, "https://", "")

  # Per-bucket ARNs (bucket + objects) keyed by the logical bucket name
  # ("video", "audio", ...) so policies can be scoped per service rather than
  # granting every role full access to every bucket.
  irsa_bucket_arn      = { for key, arn in module.s3.bucket_arns : key => arn }
  irsa_bucket_obj_arns = { for key, arn in module.s3.bucket_arns : key => "${arn}/*" }
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
            # Constrain the service account that may assume the role...
            "${local.oidc_issuer_host}:sub" = "system:serviceaccount:${var.kubernetes_namespace}:${each.key}-service-account"
            # ...and require the AWS STS audience so the token cannot be
            # replayed against a differently-scoped audience.
            "${local.oidc_issuer_host}:aud" = "sts.amazonaws.com"
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

# ==========================================================
# PER-SERVICE LEAST-PRIVILEGE S3 POLICIES
# ==========================================================
# Previously a single policy granted ALL roles Get/Put/Delete/List on ALL
# project buckets. Scoped per service based on the actual application code:
#   - gateway   : uploads videos (Put), presigns downloads (Get), lists +
#                 deletes orphan video uploads (List/Delete on video bucket);
#                 presigns audio downloads (Get/List on audio bucket).
#   - converter : downloads source video (Get/List on video bucket), writes
#                 converted audio (Put on audio bucket). No Delete needed.
#   - worker    : background converter; same access pattern as converter.
#   - auth      : no S3 access.
#   - notification : no S3 access (websocket events only).

# --- gateway ---
resource "aws_iam_policy" "irsa_s3_gateway" {
  name = "${var.project_name}-${var.environment}-gateway-irsa-s3-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "VideoBucketReadWriteDelete"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = [local.irsa_bucket_obj_arns["video"]]
      },
      {
        Sid      = "VideoBucketList"
        Effect   = "Allow"
        Action   = ["s3:ListBucket", "s3:GetBucketLocation"]
        Resource = [local.irsa_bucket_arn["video"]]
      },
      {
        Sid      = "AudioBucketReadForPresignedDownloads"
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = [local.irsa_bucket_obj_arns["audio"]]
      },
      {
        Sid      = "AudioBucketList"
        Effect   = "Allow"
        Action   = ["s3:ListBucket", "s3:GetBucketLocation"]
        Resource = [local.irsa_bucket_arn["audio"]]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "irsa_s3_gateway" {
  role       = aws_iam_role.irsa_roles["gateway"].name
  policy_arn = aws_iam_policy.irsa_s3_gateway.arn
}

# --- converter / worker (shared least-privilege policy) ---
resource "aws_iam_policy" "irsa_s3_converter" {
  name = "${var.project_name}-${var.environment}-converter-irsa-s3-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "VideoBucketReadSource"
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = [local.irsa_bucket_obj_arns["video"]]
      },
      {
        Sid      = "VideoBucketList"
        Effect   = "Allow"
        Action   = ["s3:ListBucket", "s3:GetBucketLocation"]
        Resource = [local.irsa_bucket_arn["video"]]
      },
      {
        Sid      = "AudioBucketWriteOutput"
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = [local.irsa_bucket_obj_arns["audio"]]
      },
      {
        Sid      = "AudioBucketList"
        Effect   = "Allow"
        Action   = ["s3:ListBucket", "s3:GetBucketLocation"]
        Resource = [local.irsa_bucket_arn["audio"]]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "irsa_s3_converter" {
  for_each = toset(["converter", "worker"])

  role       = aws_iam_role.irsa_roles[each.key].name
  policy_arn = aws_iam_policy.irsa_s3_converter.arn
}

# Note: auth and notification roles intentionally receive NO S3 policy
# attachment — neither service touches S3 in the application code.
