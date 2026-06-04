resource "aws_iam_role" "eks_cluster_role" {
  name = "${var.project_name}-${var.environment}-eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "eks.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role" "eks_node_role" {
  name = "${var.project_name}-${var.environment}-eks-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "worker_node_policy" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "cni_policy" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "ecr_policy" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "ebs_csi_policy" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

resource "aws_iam_role" "jenkins_role" {
  name = "${var.project_name}-${var.environment}-jenkins-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

# Custom least-privilege ECR policy for Jenkins, replacing the broad AWS-managed
# AmazonEC2ContainerRegistryPowerUser (which grants push/pull on ALL repos in the
# account). Scoped to this project's repositories (created as
# "${project_name}/<repo>" -> arn:aws:ecr:*:*:repository/<project_name>/*).
# GetAuthorizationToken is registry-wide and cannot be resource-scoped.
resource "aws_iam_policy" "jenkins_ecr" {
  name        = "${var.project_name}-${var.environment}-jenkins-ecr"
  description = "Least-privilege ECR push/pull for Jenkins, scoped to project repositories."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ECRAuthToken"
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Sid    = "ECRPushPull"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:DescribeRepositories",
          "ecr:ListImages",
          "ecr:DescribeImages"
        ]
        Resource = "arn:aws:ecr:*:*:repository/${var.project_name}/*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "jenkins_ecr" {
  role       = aws_iam_role.jenkins_role.name
  policy_arn = aws_iam_policy.jenkins_ecr.arn
}

# Least-privilege EKS policy for Jenkins: only allows kubeconfig lookup and node
# listing needed by `aws eks update-kubeconfig`. AmazonEKSClusterPolicy is the
# control-plane policy and was incorrectly attached here previously.
resource "aws_iam_policy" "jenkins_eks" {
  name        = "${var.project_name}-${var.environment}-jenkins-eks"
  description = "Least-privilege EKS read access for Jenkins CI/CD."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EKSDescribe"
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster",
          "eks:ListClusters",
          "eks:DescribeNodegroup",
          "eks:ListNodegroups",
          "eks:ListFargateProfiles"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "jenkins_eks" {
  role       = aws_iam_role.jenkins_role.name
  policy_arn = aws_iam_policy.jenkins_eks.arn
}

resource "aws_iam_role_policy_attachment" "jenkins_ec2_read" {
  role       = aws_iam_role.jenkins_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ReadOnlyAccess"
}

# SSM core — lets shutdown/restore automation (restore-jenkins.sh) run commands
# on the Jenkins host via Systems Manager without managing SSH keys.
resource "aws_iam_role_policy_attachment" "jenkins_ssm" {
  role       = aws_iam_role.jenkins_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Least-privilege S3 policy for Jenkins — scoped to the project buckets only.
# If s3_bucket_arns is empty the policy is intentionally left unattached rather
# than falling back to Resource: "*" (all buckets in the account).
resource "aws_iam_policy" "jenkins_s3" {
  count = length(var.s3_bucket_arns) > 0 ? 1 : 0

  name        = "${var.project_name}-${var.environment}-jenkins-s3"
  description = "Least-privilege S3 access for Jenkins CI/CD pipelines."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "BucketLevelAccess"
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = var.s3_bucket_arns
      },
      {
        Sid    = "ObjectLevelAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = [for arn in var.s3_bucket_arns : "${arn}/*"]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "jenkins_s3" {
  count = length(var.s3_bucket_arns) > 0 ? 1 : 0

  role       = aws_iam_role.jenkins_role.name
  policy_arn = aws_iam_policy.jenkins_s3[0].arn
}

resource "aws_iam_instance_profile" "jenkins_profile" {
  name = "${var.project_name}-${var.environment}-jenkins-profile"
  role = aws_iam_role.jenkins_role.name
}
