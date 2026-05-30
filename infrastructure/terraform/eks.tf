############################################################
# DATA SOURCES
############################################################

data "aws_caller_identity" "current" {}

data "tls_certificate" "eks" {

  url = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

############################################################
# EKS CLUSTER IAM ROLE
############################################################

resource "aws_iam_role" "eks_cluster_role" {

  name = format(
    "%s-%s-eks-cluster-role",
    var.project_name,
    var.environment
  )

  assume_role_policy = jsonencode({

    Version = "2012-10-17"

    Statement = [

      {

        Sid = "EKSClusterAssumeRole"

        Effect = "Allow"

        Principal = {
          Service = "eks.amazonaws.com"
        }

        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(
    var.common_tags,
    {
      Name = format(
        "%s-%s-eks-cluster-role",
        var.project_name,
        var.environment
      )
    }
  )
}

############################################################
# EKS CLUSTER POLICY ATTACHMENTS
############################################################

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {

  role = aws_iam_role.eks_cluster_role.name

  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role_policy_attachment" "eks_vpc_resource_controller" {

  role = aws_iam_role.eks_cluster_role.name

  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
}

############################################################
# KMS KEY FOR KUBERNETES SECRET ENCRYPTION
############################################################

resource "aws_kms_key" "eks_secrets" {

  description = format(
    "%s-%s-eks-secret-encryption",
    var.project_name,
    var.environment
  )

  deletion_window_in_days = var.kms_deletion_window_in_days

  enable_key_rotation = true

  policy = jsonencode({

    Version = "2012-10-17"

    Statement = [

      {

        Sid = "EnableRootPermissions"

        Effect = "Allow"

        Principal = {
          AWS = format(
            "arn:aws:iam::%s:root",
            data.aws_caller_identity.current.account_id
          )
        }

        Action = "kms:*"

        Resource = "*"
      },

      {

        Sid = "AllowEKSUsage"

        Effect = "Allow"

        Principal = {
          Service = "eks.amazonaws.com"
        }

        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:GenerateDataKey*"
        ]

        Resource = "*"
      }
    ]
  })

  tags = merge(
    var.common_tags,
    {
      Name = format(
        "%s-%s-eks-kms-key",
        var.project_name,
        var.environment
      )
    }
  )
}

############################################################
# EKS CLUSTER SECURITY GROUP
############################################################

resource "aws_security_group" "eks_cluster" {

  name_prefix = format(
    "%s-%s-eks-cluster-sg-",
    var.project_name,
    var.environment
  )

  description = "EKS cluster security group"

  vpc_id = var.vpc_id

  revoke_rules_on_delete = true

  ingress {

    description = "Kubernetes API access"

    from_port = 443

    to_port = 443

    protocol = "tcp"

    cidr_blocks = var.allowed_cidr_blocks
  }

  egress {

    description = "Allow outbound traffic"

    from_port = 0

    to_port = 0

    protocol = "-1"

    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.common_tags,
    {
      Name = format(
        "%s-%s-eks-cluster-sg",
        var.project_name,
        var.environment
      )
    }
  )
}

############################################################
# EKS NODE SECURITY GROUP
############################################################

resource "aws_security_group" "eks_nodes" {

  name_prefix = format(
    "%s-%s-eks-node-sg-",
    var.project_name,
    var.environment
  )

  description = "EKS worker node security group"

  vpc_id = var.vpc_id

  revoke_rules_on_delete = true

  ingress {

    description = "Node to node communication"

    from_port = 0

    to_port = 65535

    protocol = "-1"

    self = true
  }

  egress {

    description = "Allow outbound traffic"

    from_port = 0

    to_port = 0

    protocol = "-1"

    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.common_tags,
    {
      Name = format(
        "%s-%s-eks-node-sg",
        var.project_name,
        var.environment
      )
    }
  )
}

############################################################
# NODE TO CONTROL PLANE RULE
############################################################

resource "aws_security_group_rule" "node_to_cluster_https" {

  type = "ingress"

  from_port = 443

  to_port = 443

  protocol = "tcp"

  security_group_id = aws_security_group.eks_cluster.id

  source_security_group_id = aws_security_group.eks_nodes.id

  description = "Worker nodes to cluster API"
}

############################################################
# CLOUDWATCH LOG GROUP
############################################################

resource "aws_cloudwatch_log_group" "eks" {

  name = format(
    "/aws/eks/%s/cluster",
    var.cluster_name
  )

  retention_in_days = var.eks_log_retention_days

  kms_key_id = aws_kms_key.eks_secrets.arn

  tags = merge(
    var.common_tags,
    {
      Name = format(
        "%s-%s-eks-log-group",
        var.project_name,
        var.environment
      )
    }
  )
}

############################################################
# EKS CLUSTER
############################################################

resource "aws_eks_cluster" "this" {

  name = var.cluster_name

  version = var.cluster_version

  role_arn = aws_iam_role.eks_cluster_role.arn

  enabled_cluster_log_types = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler"
  ]

  access_config {

    authentication_mode = "API_AND_CONFIG_MAP"

    bootstrap_cluster_creator_admin_permissions = true
  }

  vpc_config {

    subnet_ids = var.private_subnet_ids

    endpoint_private_access = var.eks_private_endpoint_enabled

    endpoint_public_access = var.eks_public_endpoint_enabled

    public_access_cidrs = var.allowed_cidr_blocks

    security_group_ids = [
      aws_security_group.eks_cluster.id
    ]
  }

  kubernetes_network_config {

    service_ipv4_cidr = var.eks_service_ipv4_cidr
  }

  encryption_config {

    provider {

      key_arn = aws_kms_key.eks_secrets.arn
    }

    resources = [
      "secrets"
    ]
  }

  depends_on = [

    aws_iam_role_policy_attachment.eks_cluster_policy,

    aws_iam_role_policy_attachment.eks_vpc_resource_controller,

    aws_cloudwatch_log_group.eks
  ]

  lifecycle {

    prevent_destroy = false
  }

  tags = merge(
    var.common_tags,
    {
      Name = format(
        "%s-%s-eks-cluster",
        var.project_name,
        var.environment
      )
    }
  )
}

############################################################
# OIDC PROVIDER
############################################################

resource "aws_iam_openid_connect_provider" "eks" {

  client_id_list = [
    "sts.amazonaws.com"
  ]

  thumbprint_list = [
    data.tls_certificate.eks.certificates[0].sha1_fingerprint
  ]

  url = aws_eks_cluster.this.identity[0].oidc[0].issuer

  tags = var.common_tags
}

############################################################
# EKS NODE IAM ROLE
############################################################

resource "aws_iam_role" "eks_node_role" {

  name = format(
    "%s-%s-eks-node-role",
    var.project_name,
    var.environment
  )

  assume_role_policy = jsonencode({

    Version = "2012-10-17"

    Statement = [

      {

        Sid = "EKSWorkerAssumeRole"

        Effect = "Allow"

        Principal = {
          Service = "ec2.amazonaws.com"
        }

        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(
    var.common_tags,
    {
      Name = format(
        "%s-%s-eks-node-role",
        var.project_name,
        var.environment
      )
    }
  )
}

############################################################
# NODE IAM POLICY ATTACHMENTS
############################################################

resource "aws_iam_role_policy_attachment" "worker_node_policy" {

  role = aws_iam_role.eks_node_role.name

  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "cni_policy" {

  role = aws_iam_role.eks_node_role.name

  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "ecr_read_only" {

  role = aws_iam_role.eks_node_role.name

  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

############################################################
# LAUNCH TEMPLATE
############################################################

resource "aws_launch_template" "eks_nodes" {

  name_prefix = format(
    "%s-%s-eks-node-template-",
    var.project_name,
    var.environment
  )

  update_default_version = true

  vpc_security_group_ids = [
    aws_security_group.eks_nodes.id
  ]

  metadata_options {

    http_endpoint = "enabled"

    http_tokens = "required"

    http_put_response_hop_limit = 2
  }

  monitoring {

    enabled = true
  }

  block_device_mappings {

    device_name = "/dev/xvda"

    ebs {

      encrypted = true

      volume_size = var.eks_node_disk_size

      volume_type = "gp3"

      delete_on_termination = true
    }
  }

  tag_specifications {

    resource_type = "instance"

    tags = merge(
      var.common_tags,
      {
        Name = format(
          "%s-%s-eks-node",
          var.project_name,
          var.environment
        )
      }
    )
  }
}

############################################################
# EKS MANAGED NODE GROUP
############################################################

resource "aws_eks_node_group" "this" {

  cluster_name = aws_eks_cluster.this.name

  node_group_name = format(
    "%s-%s-node-group",
    var.project_name,
    var.environment
  )

  node_role_arn = aws_iam_role.eks_node_role.arn

  subnet_ids = var.private_subnet_ids

  ami_type = var.eks_node_ami_type

  capacity_type = var.eks_capacity_type

  instance_types = var.eks_node_instance_types

  disk_size = var.eks_node_disk_size

  launch_template {

    id = aws_launch_template.eks_nodes.id

    version = "$Latest"
  }

  scaling_config {

    desired_size = var.eks_desired_capacity

    min_size = var.eks_min_capacity

    max_size = var.eks_max_capacity
  }

  update_config {

    max_unavailable_percentage = var.eks_max_unavailable_percentage
  }

  node_repair_config {

    enabled = true
  }

  labels = {

    environment = var.environment

    workload = "general"
  }

  lifecycle {

    create_before_destroy = true
  }

  depends_on = [

    aws_iam_role_policy_attachment.worker_node_policy,

    aws_iam_role_policy_attachment.cni_policy,

    aws_iam_role_policy_attachment.ecr_read_only
  ]

  tags = merge(
    var.common_tags,
    {

      Name = format(
        "%s-%s-node-group",
        var.project_name,
        var.environment
      )

      "k8s.io/cluster-autoscaler/enabled" = "true"

      "k8s.io/cluster-autoscaler/${var.cluster_name}" = "owned"
    }
  )
}

############################################################
# EBS CSI DRIVER IAM ROLE
############################################################

resource "aws_iam_role" "ebs_csi_driver" {

  name = format(
    "%s-%s-ebs-csi-role",
    var.project_name,
    var.environment
  )

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

            "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub" = "system:serviceaccount:kube-system:ebs-csi-controller-sa"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ebs_csi_policy" {

  role = aws_iam_role.ebs_csi_driver.name

  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

############################################################
# EKS ADDONS
############################################################

resource "aws_eks_addon" "vpc_cni" {

  cluster_name = aws_eks_cluster.this.name

  addon_name = "vpc-cni"

  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [
    aws_eks_node_group.this
  ]

  tags = var.common_tags
}

resource "aws_eks_addon" "coredns" {

  cluster_name = aws_eks_cluster.this.name

  addon_name = "coredns"

  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [
    aws_eks_node_group.this
  ]

  tags = var.common_tags
}

resource "aws_eks_addon" "kube_proxy" {

  cluster_name = aws_eks_cluster.this.name

  addon_name = "kube-proxy"

  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [
    aws_eks_node_group.this
  ]

  tags = var.common_tags
}

resource "aws_eks_addon" "ebs_csi_driver" {

  cluster_name = aws_eks_cluster.this.name

  addon_name = "aws-ebs-csi-driver"

  service_account_role_arn = aws_iam_role.ebs_csi_driver.arn

  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [
    aws_eks_node_group.this
  ]

  tags = var.common_tags
}

############################################################
# EKS DATA SOURCES
############################################################

data "aws_eks_cluster" "this" {

  name = aws_eks_cluster.this.name
}


############################################################
# OUTPUTS
############################################################

output "eks_node_security_group_id" {

  value = aws_security_group.eks_nodes.id
}

output "eks_cluster_certificate_authority_data" {

  value = aws_eks_cluster.this.certificate_authority[0].data
}

output "eks_node_group_name" {

  value = aws_eks_node_group.this.node_group_name
}

output "eks_oidc_provider_arn" {

  value = aws_iam_openid_connect_provider.eks.arn
}