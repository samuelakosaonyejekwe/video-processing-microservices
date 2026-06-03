variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "ecr_repositories" {
  type = list(string)
}

variable "force_delete" {
  description = "Allow Terraform to delete ECR repositories that still contain images. Defaults to false for production safety."
  type        = bool
  default     = false
}
