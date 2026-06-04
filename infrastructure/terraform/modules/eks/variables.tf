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

variable "eks_node_group_name" {

  description = "Name of the EKS managed node group"

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

variable "create_managed_node_group" {

  description = <<-EOT
    Whether terraform manages the EKS managed node group. false for the existing
    live cluster (its node group is unmanaged/out-of-band — terraform must not
    create a parallel one); true for a fresh recreate so nodes are provisioned.
  EOT

  type = bool

  default = true
}

variable "cluster_encryption_kms_key_arn" {

  description = <<-EOT
    ARN of an EXISTING KMS key to use for EKS secrets encryption. When set, the
    module references this key instead of creating its own (create_kms_key=false).
    Default is the live cluster's current encryption key so terraform state matches
    reality and never attempts an (immutable) encryption_config change that would
    force a cluster replacement. Leave "" to let the module create/manage a key.
  EOT

  type = string

  default = "arn:aws:kms:eu-central-1:009850210027:key/2e99c142-566d-4f3f-a930-e456704aa00b"
}