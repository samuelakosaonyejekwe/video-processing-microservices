variable "project_name" {
  description = "Name of the project used for IAM resource naming."
  type        = string
}

variable "environment" {
  description = "Deployment environment used for IAM resource naming."
  type        = string
}

variable "s3_bucket_arns" {
  description = "ARNs of S3 buckets Jenkins is permitted to read/write. Scopes the least-privilege S3 policy."
  type        = list(string)
  default     = []
}
