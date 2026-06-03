# ==========================================================
# CUSTOMER-MANAGED KMS KEY FOR EKS SECRETS ENVELOPE ENCRYPTION
# AND CONTROL-PLANE / NODE EBS ENCRYPTION
# ==========================================================
# NOTE (one-way change on the LIVE cluster): enabling cluster_encryption_config
# below on an existing cluster is an in-place, irreversible change — once
# secrets envelope encryption is turned on it cannot be disabled.
data "aws_caller_identity" "current" {}

resource "aws_kms_key" "eks" {
  description             = "CMK for ${var.project_name}-${var.environment} EKS secrets envelope encryption and node EBS volumes"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  # Grant the account root full admin (so the key remains manageable) and the
  # EKS cluster IAM role the operations required for secrets envelope
  # encryption. create_kms_key = false on the module means the module does not
  # manage these grants for us.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EnableRootAccountAdmin"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid       = "AllowEKSClusterRoleUse"
        Effect    = "Allow"
        Principal = { AWS = var.cluster_role_arn }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey",
          "kms:CreateGrant"
        ]
        Resource = "*"
      }
    ]
  })

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-eks-cmk"
    }
  )
}

resource "aws_kms_alias" "eks" {
  name          = "alias/${var.project_name}-${var.environment}-eks"
  target_key_id = aws_kms_key.eks.key_id
}

module "eks" {

  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.31"

  cluster_name = var.eks_cluster_name

  cluster_version = var.kubernetes_version

  bootstrap_self_managed_addons = false

  vpc_id = var.vpc_id

  subnet_ids = var.subnet_ids

  enable_irsa = true

  enable_cluster_creator_admin_permissions = true

  cluster_endpoint_private_access = var.endpoint_private_access

  cluster_endpoint_public_access = var.endpoint_public_access

  cluster_endpoint_public_access_cidrs = var.public_access_cidrs

  cluster_enabled_log_types = var.enable_cluster_log_types

  # Envelope-encrypt Kubernetes secrets at rest with the CMK above.
  # One-way in-place change on an existing cluster (see KMS key note).
  # create_kms_key = false so the module uses our provider_key_arn rather than
  # creating its own second KMS key.
  create_kms_key = false

  cluster_encryption_config = {
    provider_key_arn = aws_kms_key.eks.arn
    resources        = ["secrets"]
  }

  # Encrypt the control-plane CloudWatch log group with the CMK and retain logs
  # for a bounded period instead of indefinitely.
  create_cloudwatch_log_group            = true
  cloudwatch_log_group_retention_in_days = 90
  cloudwatch_log_group_kms_key_id        = aws_kms_key.eks.arn

  eks_managed_node_groups = {

    (var.eks_node_group_name) = {

      instance_types = [
        var.eks_node_instance_type
      ]

      desired_size = var.eks_desired_size

      min_size = var.eks_min_size

      max_size = var.eks_max_size

      capacity_type = var.capacity_type

      ami_type = var.ami_type

      vpc_security_group_ids = var.security_group_ids

      # Encrypted root EBS volume with the EKS CMK.
      # NOTE: changing block_device_mappings / metadata_options forces a new
      # launch template version and triggers a rolling NODE REPLACEMENT on apply.
      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size           = var.node_disk_size
            volume_type           = "gp3"
            encrypted             = true
            kms_key_id            = aws_kms_key.eks.arn
            delete_on_termination = true
          }
        }
      }

      # Enforce IMDSv2 (token required) and limit the hop count so containers
      # cannot reach the node instance metadata / role credentials.
      metadata_options = {
        http_endpoint               = "enabled"
        http_tokens                 = "required"
        http_put_response_hop_limit = 1
      }

      update_config = {

        max_unavailable = var.max_unavailable
      }

      iam_role_arn = var.node_role_arn

      tags = {
        Name = "${var.project_name}-${var.environment}-eks-worker"
      }

      launch_template_tags = {
        Name = "${var.project_name}-${var.environment}-eks-worker"
      }
    }
  }

  create_iam_role = false

  iam_role_arn = var.cluster_role_arn

  cluster_addons = {
    vpc-cni = {
      most_recent = true
    }
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
  }

  tags = merge(
    {
      Environment = var.environment
      Terraform   = "true"
      Project     = var.project_name
    },
    var.tags
  )

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.ecr_readonly
  ]
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {

  role = regex(
    "[^/]+$",
    var.cluster_role_arn
  )

  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {

  role = regex(
    "[^/]+$",
    var.node_role_arn
  )

  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {

  role = regex(
    "[^/]+$",
    var.node_role_arn
  )

  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "ecr_readonly" {

  role = regex(
    "[^/]+$",
    var.node_role_arn
  )

  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}