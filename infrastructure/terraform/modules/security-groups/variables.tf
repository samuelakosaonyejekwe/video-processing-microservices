variable "project_name" {

  description = "Project name"

  type = string
}

variable "environment" {

  description = "Deployment environment"

  type = string
}

variable "vpc_id" {

  description = "VPC ID"

  type = string
}

variable "vpc_cidr" {

  description = "VPC CIDR block"

  type = string
}

variable "allowed_cidr_blocks" {

  description = "Allowed CIDR blocks for administrative access"

  type = list(string)
}

variable "jenkins_allowed_cidr_blocks" {

  description = "CIDR blocks permitted to reach the Jenkins web UI (port 8080). SECURITY: narrow this to your admin/VPN/office IPs — defaults to allowed_cidr_blocks (likely 0.0.0.0/0) only to preserve existing access. Do NOT leave this open to the world in production."

  type = list(string)
}