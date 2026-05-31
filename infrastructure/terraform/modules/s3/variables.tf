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

variable "s3_buckets" {

  description = "Map of S3 bucket configurations keyed by logical name."

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
    cors_allowed_origins               = optional(list(string), ["*"])
    cors_expose_headers                = optional(list(string), [])
    cors_max_age_seconds               = optional(number, 3000)
    prefix_lifecycle_rules = optional(list(object({
      id              = string
      prefix          = string
      expiration_days = number
    })), [])
  }))
}

variable "tags" {

  description = "Additional tags applied to S3 resources."

  type = map(string)

  default = {}
}