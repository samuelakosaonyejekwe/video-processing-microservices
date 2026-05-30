module "eks" {

  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.31"

  cluster_name = var.eks_cluster_name

  cluster_version = var.kubernetes_version

  vpc_id = var.vpc_id

  subnet_ids = var.subnet_ids

  enable_irsa = true

  cluster_endpoint_private_access = var.endpoint_private_access

  cluster_endpoint_public_access = var.endpoint_public_access

  cluster_endpoint_public_access_cidrs = var.public_access_cidrs

  cluster_enabled_log_types = var.enable_cluster_log_types

  eks_managed_node_groups = {

    default = {

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
    }
  }

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
    aws-ebs-csi-driver = {
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