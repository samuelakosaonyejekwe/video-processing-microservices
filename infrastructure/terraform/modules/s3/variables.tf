variable "project_name" {

  description = "Project name used for naming and tagging S3 resources."

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

    condition = contains(
      [
        "development",
        "dev",
        "staging",
        "test",
        "production",
        "prod"
      ],
      lower(var.environment)
    )

    error_message = "environment must be a valid deployment environment."
  }
}

variable "aws_region" {

  description = "AWS region where S3 resources will be created."

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

variable "bucket_name_prefix" {

  description = "Prefix used for generating S3 bucket names."

  type = string

  validation {

    condition = (
      length(
        trimspace(var.bucket_name_prefix)
      ) > 0
    )

    error_message = "bucket_name_prefix must not be empty."
  }
}

variable "bucket_purpose" {

  description = "Logical purpose of the bucket."

  type = string

  validation {

    condition = (
      length(
        trimspace(var.bucket_purpose)
      ) > 0
    )

    error_message = "bucket_purpose must not be empty."
  }
}

variable "force_destroy" {

  description = "Allow Terraform to destroy non-empty buckets."

  type = bool

  default = false
}

variable "versioning_enabled" {

  description = "Enable S3 bucket versioning."

  type = bool

  default = true
}

variable "enable_encryption" {

  description = "Enable server-side encryption for the bucket."

  type = bool

  default = true
}

variable "sse_algorithm" {

  description = "Server-side encryption algorithm."

  type = string

  default = "AES256"

  validation {

    condition = contains(
      [
        "AES256",
        "aws:kms"
      ],
      var.sse_algorithm
    )

    error_message = "sse_algorithm must be AES256 or aws:kms."
  }
}

variable "kms_master_key_id" {

  description = "Optional KMS key ID when using aws:kms encryption."

  type = string

  default = null
}

variable "block_public_acls" {

  description = "Block public ACLs."

  type = bool

  default = true
}

variable "block_public_policy" {

  description = "Block public bucket policies."

  type = bool

  default = true
}

variable "ignore_public_acls" {

  description = "Ignore public ACLs."

  type = bool

  default = true
}

variable "restrict_public_buckets" {

  description = "Restrict public bucket settings."

  type = bool

  default = true
}

variable "enable_lifecycle_rules" {

  description = "Enable lifecycle management rules."

  type = bool

  default = true
}

variable "lifecycle_transition_days" {

  description = "Number of days before transitioning objects."

  type = number

  default = 30
}

variable "lifecycle_expiration_days" {

  description = "Number of days before expiring objects."

  type = number

  default = 365
}

variable "enable_access_logging" {

  description = "Enable S3 server access logging."

  type = bool

  default = false
}

variable "logging_bucket_name" {

  description = "Target bucket for S3 access logs."

  type = string

  default = null
}

variable "logging_prefix" {

  description = "Prefix for S3 access logs."

  type = string

  default = "logs/"
}

variable "cors_allowed_origins" {

  description = "Allowed CORS origins."

  type = list(string)

  default = []
}

variable "cors_allowed_methods" {

  description = "Allowed CORS methods."

  type = list(string)

  default = [
    "GET",
    "PUT",
    "POST",
    "DELETE",
    "HEAD"
  ]
}

variable "cors_allowed_headers" {

  description = "Allowed CORS headers."

  type = list(string)

  default = [
    "*"
  ]
}

variable "cors_expose_headers" {

  description = "Headers exposed to clients."

  type = list(string)

  default = []
}

variable "cors_max_age_seconds" {

  description = "CORS max age in seconds."

  type = number

  default = 3000
}

variable "tags" {

  description = "Additional tags applied to S3 resources."

  type = map(string)

  default = {}
}