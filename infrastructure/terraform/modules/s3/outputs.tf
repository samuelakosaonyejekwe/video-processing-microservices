output "bucket_names" {
  description = "Map of logical bucket keys to bucket names."
  value       = { for key, bucket in aws_s3_bucket.this : key => bucket.id }
}

output "bucket_arns" {
  description = "Map of logical bucket keys to bucket ARNs."
  value       = { for key, bucket in aws_s3_bucket.this : key => bucket.arn }
}

output "kms_key_arn" {
  description = "ARN of the customer-managed KMS key used for bucket encryption."
  value       = aws_kms_key.s3.arn
}
