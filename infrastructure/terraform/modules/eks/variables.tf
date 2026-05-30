variable "project_name" {

  description = "Project name"

  type = string
}

variable "environment" {

  description = "Deployment environment"

  type = string
}

variable "eks_cluster_name" {

  description = "EKS cluster name"

  type = string
}

variable "vpc_id" {

  description = "VPC ID"

  type = string
}

variable "subnet_ids" {

  description = "Private subnet IDs for EKS worker nodes"

  type = list(string)
}

variable "cluster_role_arn" {

  description = "IAM role ARN for EKS cluster"

  type = string
}

variable "node_role_arn" {

  description = "IAM role ARN for EKS node group"

  type = string
}

variable "security_group_ids" {

  description = "Security groups attached to EKS cluster"

  type = list(string)
}

variable "eks_node_instance_type" {

  description = "EKS worker node EC2 instance type"

  type = string
}

variable "eks_desired_size" {

  description = "Desired number of EKS worker nodes"

  type = number
}

variable "eks_min_size" {

  description = "Minimum number of EKS worker nodes"

  type = number
}

variable "eks_max_size" {

  description = "Maximum number of EKS worker nodes"

  type = number
}

variable "kubernetes_version" {

  description = "Kubernetes version"

  type = string
}

variable "enable_cluster_log_types" {

  description = "EKS control plane logging types"

  type = list(string)
}

variable "endpoint_private_access" {

  description = "Enable private API server endpoint"

  type = bool
}

variable "endpoint_public_access" {

  description = "Enable public API server endpoint"

  type = bool
}

variable "public_access_cidrs" {

  description = "Allowed CIDR blocks for public Kubernetes API access"

  type = list(string)
}

variable "node_disk_size" {

  description = "EKS node root disk size"

  type = number
}

variable "capacity_type" {

  description = "EKS node group capacity type"

  type = string
}

variable "ami_type" {

  description = "AMI type for EKS worker nodes"

  type = string
}

variable "max_unavailable" {

  description = "Maximum unavailable nodes during update"

  type = number
}

variable "tags" {

  description = "Common resource tags"

  type = map(string)

  default = {}
}