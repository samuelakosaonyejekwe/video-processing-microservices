variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "ecr_repositories" {
  type = list(string)
}
