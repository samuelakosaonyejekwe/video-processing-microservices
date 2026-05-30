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

  validation {

    condition = (
      var.eks_max_size >= var.eks_min_size
    )

    error_message = "eks_max_size must be greater than or equal to eks_min_size."
  }
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
# Auto-added missing variables for terraform validate
variable "ami_type" {
  type = any
}

variable "aws_load_balancer_controller_chart" {
  type = any
}

variable "aws_load_balancer_controller_name" {
  type = any
}

variable "aws_load_balancer_controller_namespace" {
  type = any
}

variable "aws_load_balancer_controller_repository" {
  type = any
}

variable "awscli_zip_url" {
  type = any
}

variable "capacity_type" {
  type = any
}

variable "cluster_autoscaler_chart" {
  type = any
}

variable "cluster_autoscaler_namespace" {
  type = any
}

variable "cluster_autoscaler_release_name" {
  type = any
}

variable "cluster_autoscaler_repository" {
  type = any
}

variable "cluster_autoscaler_timeout" {
  type = any
}

variable "cluster_name" {
  type = any
}

variable "cluster_version" {
  type = any
}

variable "common_tags" {
  type = any
}

variable "docker_gpg_url" {
  type = any
}

variable "docker_repo_url" {
  type = any
}

variable "ebs_csi_driver_atomic" {
  type = any
}

variable "ebs_csi_driver_chart" {
  type = any
}

variable "ebs_csi_driver_cleanup_on_fail" {
  type = any
}

variable "ebs_csi_driver_create_namespace" {
  type = any
}

variable "ebs_csi_driver_dependency_update" {
  type = any
}

variable "ebs_csi_driver_namespace" {
  type = any
}

variable "ebs_csi_driver_release_name" {
  type = any
}

variable "ebs_csi_driver_repository" {
  type = any
}

variable "ebs_csi_driver_timeout" {
  type = any
}

variable "ebs_csi_driver_wait" {
  type = any
}

variable "ecr_repositories" {
  type = any
}

variable "eks_capacity_type" {
  type = any
}

variable "eks_desired_capacity" {
  type = any
}

variable "eks_log_retention_days" {
  type = any
}

variable "eks_max_capacity" {
  type = any
}

variable "eks_max_unavailable_percentage" {
  type = any
}

variable "eks_min_capacity" {
  type = any
}

variable "eks_node_ami_type" {
  type = any
}

variable "eks_node_disk_size" {
  type = any
}

variable "eks_node_instance_types" {
  type = any
}

variable "eks_private_endpoint_enabled" {
  type = any
}

variable "eks_public_endpoint_enabled" {
  type = any
}

variable "eks_service_ipv4_cidr" {
  type = any
}

variable "eksctl_download_url" {
  type = any
}

variable "enable_cluster_log_types" {
  type = any
}

variable "endpoint_private_access" {
  type = any
}

variable "endpoint_public_access" {
  type = any
}

variable "hashicorp_gpg_url" {
  type = any
}

variable "hashicorp_repo_url" {
  type = any
}

variable "helm_install_script_url" {
  type = any
}

variable "jenkins_agent_port" {
  type = any
}

variable "jenkins_container_image" {
  type = any
}

variable "jenkins_container_name" {
  type = any
}

variable "jenkins_gpg_url" {
  type = any
}

variable "jenkins_host_port" {
  type = any
}

variable "jenkins_instance_type" {
  type = any
}

variable "jenkins_repo_url" {
  type = any
}

variable "jenkins_root_volume_size" {
  type = any
}

variable "jenkins_volume_name" {
  type = any
}

variable "kms_deletion_window_in_days" {
  type = any
}

variable "kubectl_binary_base_url" {
  type = any
}

variable "kubectl_stable_url" {
  type = any
}

variable "kubernetes_namespace" {
  type = any
}

variable "kubernetes_version" {
  type = any
}

variable "max_unavailable" {
  type = any
}

variable "metrics_server_atomic" {
  type = any
}

variable "metrics_server_chart" {
  type = any
}

variable "metrics_server_cleanup_on_fail" {
  type = any
}

variable "metrics_server_create_namespace" {
  type = any
}

variable "metrics_server_dependency_update" {
  type = any
}

variable "metrics_server_namespace" {
  type = any
}

variable "metrics_server_release_name" {
  type = any
}

variable "metrics_server_repository" {
  type = any
}

variable "metrics_server_timeout" {
  type = any
}

variable "metrics_server_wait" {
  type = any
}

variable "node_disk_size" {
  type = any
}

variable "private_subnet_ids" {
  type = any
}

variable "public_access_cidrs" {
  type = any
}

variable "s3_bucket_name" {
  type = any
}

variable "tags" {
  type = any
}

variable "ubuntu_ami_name_filter" {
  type = any
}

variable "ubuntu_ami_owners" {
  type = any
}

variable "vpc_id" {
  type = any
}

