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

  # Secrets encryption: when an existing key ARN is supplied (the default — the
  # live cluster's current key), reference it instead of creating a new key. This
  # keeps terraform state aligned with the live, immutable encryption_config and
  # prevents a catastrophic key-change-forced cluster replacement. When the ARN is
  # "", fall back to the module-managed key (fresh-cluster / recreate path).
  create_kms_key = var.cluster_encryption_kms_key_arn == "" ? true : false

  cluster_encryption_config = {
    provider_key_arn = var.cluster_encryption_kms_key_arn
    resources        = ["secrets"]
  }

  # Gate the managed node group. The LIVE cluster's node group is unmanaged
  # (created out-of-band), so for the existing cluster this is false → terraform
  # leaves the running nodes untouched. On a fresh recreate (full restart) it is
  # true so terraform provisions the node group. start-platform.sh passes
  # -var=create_managed_node_group=true for the recreate path.
  eks_managed_node_groups = var.create_managed_node_group ? {

    (var.eks_node_group_name) = {

      instance_types = [
        var.eks_node_instance_type
      ]

      desired_size = var.eks_desired_size

      min_size = var.eks_min_size

      max_size = var.eks_max_size

      disk_size = var.node_disk_size

      capacity_type = var.capacity_type

      ami_type = var.ami_type

      vpc_security_group_ids = var.security_group_ids

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
  } : {}

  create_iam_role = false

  iam_role_arn = var.cluster_role_arn

  cluster_addons = {
    vpc-cni = {
      most_recent = true
      # Install the CNI BEFORE the managed node group. Without this, a fresh
      # recreate deadlocks: the node group create waits for its nodes to be
      # Ready, but nodes can't be Ready until the CNI exists — and the CNI addon
      # is created AFTER compute by default. (The live cluster never hit this
      # because its node group was created out-of-band; create_managed_node_group
      # makes terraform own it, exposing the ordering.)
      before_compute = true
      # Enable Kubernetes NetworkPolicy enforcement via the AWS VPC CNI
      # network-policy agent, so the default-deny + per-app NetworkPolicies are
      # actually enforced rather than declarative. Enforcing mode defaults to
      # "standard" (allows traffic until a policy reconciles, avoiding startup
      # deadlocks); leave it at the default.
      configuration_values = jsonencode({
        enableNetworkPolicy = "true"
      })
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