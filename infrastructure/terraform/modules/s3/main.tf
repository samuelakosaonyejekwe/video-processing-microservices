# ==========================================================
# CUSTOMER-MANAGED KMS KEY FOR BUCKET ENCRYPTION
# ==========================================================

resource "aws_kms_key" "s3" {
  description             = "CMK for ${var.project_name}-${var.environment} S3 bucket encryption"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-s3-cmk"
    }
  )
}

resource "aws_kms_alias" "s3" {
  name          = "alias/${var.project_name}-${var.environment}-s3"
  target_key_id = aws_kms_key.s3.key_id
}

resource "aws_s3_bucket" "this" {

  for_each = var.s3_buckets

  bucket = lookup(
    each.value,
    "bucket_name",
    lower(
      join(
        "-",
        compact([
          var.project_name,
          var.environment,
          each.key
        ])
      )
    )
  )

  force_destroy = lookup(
    each.value,
    "force_destroy",
    false
  )

  tags = merge(

    var.tags,

    {

      Name = lower(
        join(
          "-",
          compact([
            var.project_name,
            var.environment,
            each.key
          ])
        )
      )

      BucketType = each.key
    }
  )
}

# ==========================================================
# VERSIONING
# ==========================================================

resource "aws_s3_bucket_versioning" "this" {

  for_each = var.s3_buckets

  bucket = aws_s3_bucket.this[each.key].id

  versioning_configuration {

    status = lookup(
      var.s3_buckets[each.key],
      "versioning_enabled",
      true
    ) ? "Enabled" : "Suspended"
  }
}

# ==========================================================
# SERVER SIDE ENCRYPTION
# ==========================================================

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {

  for_each = var.s3_buckets

  bucket = aws_s3_bucket.this[each.key].id

  rule {

    apply_server_side_encryption_by_default {

      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.s3.arn
    }

    bucket_key_enabled = true
  }
}

# ==========================================================
# PUBLIC ACCESS BLOCK
# ==========================================================

resource "aws_s3_bucket_public_access_block" "this" {

  for_each = var.s3_buckets

  bucket = aws_s3_bucket.this[each.key].id

  block_public_acls = true

  block_public_policy = true

  ignore_public_acls = true

  restrict_public_buckets = true
}

# ==========================================================
# BUCKET OWNERSHIP
# ==========================================================

resource "aws_s3_bucket_ownership_controls" "this" {

  for_each = var.s3_buckets

  bucket = aws_s3_bucket.this[each.key].id

  rule {

    object_ownership = "BucketOwnerPreferred"
  }
}

# ==========================================================
# ACL CONFIGURATION
# ==========================================================

resource "aws_s3_bucket_acl" "this" {

  for_each = var.s3_buckets

  depends_on = [
    aws_s3_bucket_ownership_controls.this,
    aws_s3_bucket_public_access_block.this
  ]

  bucket = aws_s3_bucket.this[each.key].id

  acl = "private"
}

# ==========================================================
# LIFECYCLE RULES
# ==========================================================

resource "aws_s3_bucket_lifecycle_configuration" "this" {

  for_each = var.s3_buckets

  bucket = aws_s3_bucket.this[each.key].id

  rule {
    id = "default-lifecycle"

    status = lookup(
      var.s3_buckets[each.key],
      "lifecycle_enabled",
      true
    ) ? "Enabled" : "Disabled"

    filter {}

    dynamic "expiration" {

      for_each = lookup(
        var.s3_buckets[each.key],
        "expiration_days",
        null
      ) != null ? [1] : []

      content {

        days = lookup(
          var.s3_buckets[each.key],
          "expiration_days",
          30
        )
      }
    }

    dynamic "transition" {

      for_each = lookup(
        var.s3_buckets[each.key],
        "transition_to_ia_days",
        null
      ) != null ? [1] : []

      content {

        days = lookup(
          var.s3_buckets[each.key],
          "transition_to_ia_days",
          30
        )

        storage_class = "STANDARD_IA"
      }
    }

    dynamic "transition" {

      for_each = lookup(
        var.s3_buckets[each.key],
        "transition_to_glacier_days",
        null
      ) != null ? [1] : []

      content {

        days = lookup(
          var.s3_buckets[each.key],
          "transition_to_glacier_days",
          90
        )

        storage_class = "GLACIER"
      }
    }

    noncurrent_version_expiration {

      noncurrent_days = lookup(
        var.s3_buckets[each.key],
        "noncurrent_version_expiration_days",
        30
      )
    }
  }

  dynamic "rule" {
    for_each = lookup(
      var.s3_buckets[each.key],
      "prefix_lifecycle_rules",
      []
    )

    content {
      id     = rule.value.id
      status = "Enabled"

      filter {
        prefix = rule.value.prefix
      }

      expiration {
        days = rule.value.expiration_days
      }
    }
  }
}

# ==========================================================
# OPTIONAL CORS
# ==========================================================

resource "aws_s3_bucket_cors_configuration" "this" {

  for_each = {

    for bucket_name, bucket_config in var.s3_buckets :

    bucket_name => bucket_config

    if lookup(
      bucket_config,
      "enable_cors",
      false
    )
  }

  bucket = aws_s3_bucket.this[
    each.key
  ].id

  cors_rule {

    allowed_headers = lookup(
      each.value,
      "cors_allowed_headers",
      ["*"]
    )

    allowed_methods = lookup(
      each.value,
      "cors_allowed_methods",
      [
        "GET",
        "PUT",
        "POST",
        "HEAD"
      ]
    )

    allowed_origins = lookup(
      each.value,
      "cors_allowed_origins",
      ["*"]
    )

    expose_headers = lookup(
      each.value,
      "cors_expose_headers",
      ["ETag"]
    )

    max_age_seconds = lookup(
      each.value,
      "cors_max_age_seconds",
      3000
    )
  }
}
