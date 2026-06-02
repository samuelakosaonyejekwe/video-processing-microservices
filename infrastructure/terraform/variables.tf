variable "project_name" {

  description = "Logical project name used across infrastructure resources."

  type = string

  validation {

    condition = (
      length(
        trimspace(var.project_name)
      ) > 0
    )

    error_message = "project_name must not be empty."
  }
}

variable "environment" {

  description = "Deployment environment name."

  type = string

  validation {

    condition = (
      length(
        trimspace(var.environment)
      ) > 0
    )

    error_message = "environment must not be empty."
  }
}

variable "aws_region" {

  description = "AWS region for infrastructure deployment."

  type = string

  validation {

    condition = (
      length(
        trimspace(var.aws_region)
      ) > 0
    )

    error_message = "aws_region must not be empty."
  }
}

variable "eks_cluster_name" {

  description = "EKS cluster name."

  type = string

  validation {

    condition = (
      length(
        trimspace(var.eks_cluster_name)
      ) > 0
    )

    error_message = "eks_cluster_name must not be empty."
  }
}

variable "eks_node_instance_type" {

  description = "EKS worker node EC2 instance type."

  type = string

  validation {

    condition = (
      length(
        trimspace(var.eks_node_instance_type)
      ) > 0
    )

    error_message = "eks_node_instance_type must not be empty."
  }
}

variable "eks_desired_size" {

  description = "Desired number of EKS worker nodes."

  type = number

  validation {

    condition = (
      var.eks_desired_size >= 1
    )

    error_message = "eks_desired_size must be greater than or equal to 1."
  }
}

variable "eks_min_size" {

  description = "Minimum number of EKS worker nodes."

  type = number

  validation {

    condition = (
      var.eks_min_size >= 1
    )

    error_message = "eks_min_size must be greater than or equal to 1."
  }
}

variable "eks_max_size" {

  description = "Maximum number of EKS worker nodes."

  type = number
}

variable "vpc_cidr" {

  description = "CIDR block used for the VPC."

  type = string

  validation {

    condition = can(
      cidrhost(var.vpc_cidr, 0)
    )

    error_message = "vpc_cidr must be a valid CIDR block."
  }
}

variable "availability_zones" {

  description = "Availability zones used across infrastructure."

  type = list(string)

  validation {

    condition = (
      length(var.availability_zones) > 0
    )

    error_message = "availability_zones must contain at least one availability zone."
  }
}

variable "public_subnet_cidrs" {

  description = "CIDR blocks for public subnets."

  type = list(string)

  validation {

    condition = (
      length(var.public_subnet_cidrs) > 0
    )

    error_message = "public_subnet_cidrs must contain at least one CIDR block."
  }
}

variable "private_subnet_cidrs" {

  description = "CIDR blocks for private subnets."

  type = list(string)

  validation {

    condition = (
      length(var.private_subnet_cidrs) > 0
    )

    error_message = "private_subnet_cidrs must contain at least one CIDR block."
  }
}

variable "enable_nat_gateway" {

  description = "Enable NAT gateway deployment."

  type = bool

  default = true
}

variable "single_nat_gateway" {

  description = "Use a single shared NAT gateway."

  type = bool

  default = true
}

variable "allowed_cidr_blocks" {

  description = "Allowed CIDR blocks for ingress access."

  type = list(string)

  validation {

    condition = (
      length(var.allowed_cidr_blocks) > 0
    )

    error_message = "allowed_cidr_blocks must contain at least one CIDR block."
  }
}

variable "keda_release_name" {

  description = "KEDA Helm release name."

  type = string

  validation {

    condition = (
      length(
        trimspace(var.keda_release_name)
      ) > 0
    )

    error_message = "keda_release_name must not be empty."
  }
}

variable "keda_helm_repository" {

  description = "KEDA Helm repository URL."

  type = string

  validation {

    condition = (
      length(
        trimspace(var.keda_helm_repository)
      ) > 0
    )

    error_message = "keda_helm_repository must not be empty."
  }
}

variable "keda_chart_name" {

  description = "KEDA Helm chart name."

  type = string

  validation {

    condition = (
      length(
        trimspace(var.keda_chart_name)
      ) > 0
    )

    error_message = "keda_chart_name must not be empty."
  }
}

variable "keda_namespace" {

  description = "KEDA Kubernetes namespace."

  type = string

  validation {

    condition = (
      length(
        trimspace(var.keda_namespace)
      ) > 0
    )

    error_message = "keda_namespace must not be empty."
  }
}

variable "domain_name" {

  description = "Primary application domain name."

  type = string

  validation {

    condition = (
      length(
        trimspace(var.domain_name)
      ) > 0
    )

    error_message = "domain_name must not be empty."
  }
}

variable "hosted_zone_name" {

  description = "Route53 hosted zone name."

  type = string

  validation {

    condition = (
      length(
        trimspace(var.hosted_zone_name)
      ) > 0
    )

    error_message = "hosted_zone_name must not be empty."
  }
}

variable "acm_certificate_arn" {

  description = "ACM certificate ARN used for HTTPS."

  type = string

  validation {

    condition = (
      length(
        trimspace(var.acm_certificate_arn)
      ) > 0
    )

    error_message = "acm_certificate_arn must not be empty."
  }
}

variable "ami_type" {
  type    = string
  default = "AL2_x86_64"
}

variable "aws_load_balancer_controller_chart" {
  type    = string
  default = "aws-load-balancer-controller"
}

variable "aws_load_balancer_controller_name" {
  type    = string
  default = "aws-load-balancer-controller"
}

variable "aws_load_balancer_controller_namespace" {
  type    = string
  default = "kube-system"
}

variable "aws_load_balancer_controller_repository" {
  type    = string
  default = "https://aws.github.io/eks-charts"
}

variable "awscli_zip_url" {
  type    = string
  default = "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip"
}

variable "capacity_type" {
  type    = string
  default = "ON_DEMAND"
}

variable "cluster_autoscaler_chart" {
  type    = string
  default = "cluster-autoscaler"
}

variable "cluster_autoscaler_namespace" {
  type    = string
  default = "kube-system"
}

variable "cluster_autoscaler_release_name" {
  type    = string
  default = "cluster-autoscaler"
}

variable "cluster_autoscaler_repository" {
  type    = string
  default = "https://kubernetes.github.io/autoscaler"
}

variable "cluster_autoscaler_timeout" {
  type    = number
  default = 600
}

variable "docker_gpg_url" {
  type    = string
  default = "https://download.docker.com/linux/ubuntu/gpg"
}

variable "docker_repo_url" {
  type    = string
  default = "https://download.docker.com/linux/ubuntu"
}

variable "ecr_repositories" {
  type = list(string)
  default = [
    "gateway-service",
    "auth-service",
    "converter-service",
    "notification-service",
  ]
}

variable "eksctl_download_url" {
  type    = string
  default = "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_Linux_amd64.tar.gz"
}

variable "enable_cluster_log_types" {
  type    = list(string)
  default = ["api", "audit"]
}

variable "endpoint_private_access" {
  type    = bool
  default = true
}

variable "endpoint_public_access" {
  type    = bool
  default = true
}

variable "hashicorp_gpg_url" {
  type    = string
  default = "https://apt.releases.hashicorp.com/gpg"
}

variable "hashicorp_repo_url" {
  type    = string
  default = "https://apt.releases.hashicorp.com"
}

variable "helm_install_script_url" {
  type    = string
  default = "https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3"
}

variable "jenkins_agent_port" {
  type    = number
  default = 50000
}

variable "jenkins_container_image" {
  type    = string
  default = "jenkins/jenkins:lts"
}

variable "jenkins_container_name" {
  type    = string
  default = "jenkins"
}

variable "jenkins_gpg_url" {
  type    = string
  default = "https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key"
}

variable "jenkins_host_port" {
  type    = number
  default = 8080
}

variable "jenkins_instance_type" {
  type    = string
  default = "t3.medium"
}

variable "jenkins_repo_url" {
  type    = string
  default = "https://pkg.jenkins.io/debian-stable binary/"
}

variable "jenkins_root_volume_size" {
  type    = number
  default = 50
}

variable "jenkins_volume_name" {
  type    = string
  default = "jenkins-data"
}

variable "kubectl_binary_base_url" {
  type    = string
  default = "https://dl.k8s.io/release"
}

variable "kubectl_stable_url" {
  type    = string
  default = "https://dl.k8s.io/release/stable.txt"
}

variable "kubernetes_namespace" {
  type    = string
  default = "video-processing"
}

variable "kubernetes_version" {
  type    = string
  default = "1.29"
}

variable "max_unavailable" {
  type    = number
  default = 1
}

variable "metrics_server_atomic" {
  type    = bool
  default = true
}

variable "metrics_server_chart" {
  type    = string
  default = "metrics-server"
}

variable "metrics_server_cleanup_on_fail" {
  type    = bool
  default = true
}

variable "metrics_server_create_namespace" {
  type    = bool
  default = true
}

variable "metrics_server_dependency_update" {
  type    = bool
  default = true
}

variable "metrics_server_namespace" {
  type    = string
  default = "kube-system"
}

variable "metrics_server_release_name" {
  type    = string
  default = "metrics-server"
}

variable "metrics_server_repository" {
  type    = string
  default = "https://kubernetes-sigs.github.io/metrics-server/"
}

variable "metrics_server_timeout" {
  type    = number
  default = 600
}

variable "metrics_server_wait" {
  type    = bool
  default = true
}

variable "node_disk_size" {
  type    = number
  default = 50
}

variable "public_access_cidrs" {
  description = "CIDR blocks permitted to reach the EKS API public endpoint. Must be explicitly set — no default to prevent accidental world-wide exposure."
  type        = list(string)
  default     = []

  validation {
    condition     = length(var.public_access_cidrs) > 0
    error_message = "public_access_cidrs must contain at least one CIDR block. Set to your VPN/office CIDRs; do not use 0.0.0.0/0 in production."
  }
}

variable "s3_bucket_name" {
  description = "Primary S3 bucket name for video uploads. Must be globally unique — set explicitly in terraform.tfvars."
  type        = string

  validation {
    condition     = length(trimspace(var.s3_bucket_name)) > 0
    error_message = "s3_bucket_name must not be empty."
  }
}

variable "s3_video_bucket_name" {
  description = "S3 bucket name for raw video uploads. Must be globally unique — set explicitly in terraform.tfvars."
  type        = string

  validation {
    condition     = length(trimspace(var.s3_video_bucket_name)) > 0
    error_message = "s3_video_bucket_name must not be empty."
  }
}

variable "s3_audio_bucket_name" {
  description = "S3 bucket name for converted audio outputs. Must be globally unique — set explicitly in terraform.tfvars."
  type        = string

  validation {
    condition     = length(trimspace(var.s3_audio_bucket_name)) > 0
    error_message = "s3_audio_bucket_name must not be empty."
  }
}

variable "s3_buckets" {
  type = map(object({
    bucket_name                        = optional(string)
    force_destroy                      = optional(bool, false)
    versioning_enabled                 = optional(bool, true)
    lifecycle_enabled                  = optional(bool, true)
    expiration_days                    = optional(number)
    transition_to_ia_days              = optional(number)
    transition_to_glacier_days         = optional(number)
    noncurrent_version_expiration_days = optional(number, 30)
    sse_algorithm                      = optional(string, "AES256")
    enable_cors                        = optional(bool, false)
    cors_allowed_headers               = optional(list(string), ["*"])
    cors_allowed_methods               = optional(list(string), ["GET", "PUT", "POST", "HEAD"])
    cors_allowed_origins               = optional(list(string), [])
    cors_expose_headers                = optional(list(string), [])
    cors_max_age_seconds               = optional(number, 3000)
    prefix_lifecycle_rules = optional(list(object({
      id              = string
      prefix          = string
      expiration_days = number
    })), [])
  }))

  default = {}
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "ubuntu_ami_name_filter" {
  type    = list(string)
  default = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
}

variable "ubuntu_ami_owners" {
  type    = list(string)
  default = ["099720109477"]
}

