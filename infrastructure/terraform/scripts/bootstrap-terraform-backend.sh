#!/bin/bash

set -euo pipefail

: "${AWS_REGION:?Missing AWS_REGION}"

: "${TF_STATE_BUCKET:?Missing TF_STATE_BUCKET}"

: "${TF_LOCK_TABLE:?Missing TF_LOCK_TABLE}"

# Optional: alias of a CMK used to encrypt the state bucket. Created below if it
# does not already exist. Override TF_STATE_KMS_ALIAS to reuse an existing key.
TF_STATE_KMS_ALIAS="${TF_STATE_KMS_ALIAS:-alias/terraform-state}"

if ! aws s3api head-bucket \
  --bucket "${TF_STATE_BUCKET}" \
  2>/dev/null
then

  aws s3api create-bucket \
    --bucket "${TF_STATE_BUCKET}" \
    --region "${AWS_REGION}" \
    --create-bucket-configuration \
      LocationConstraint="${AWS_REGION}"

fi

aws s3api put-bucket-versioning \
  --bucket "${TF_STATE_BUCKET}" \
  --versioning-configuration Status=Enabled

# ----------------------------------------------------------------------------
# Block ALL public access on the state bucket (idempotent — safe to re-run).
# ----------------------------------------------------------------------------
aws s3api put-public-access-block \
  --bucket "${TF_STATE_BUCKET}" \
  --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

# ----------------------------------------------------------------------------
# Ensure a customer-managed KMS key (CMK) exists for state-bucket encryption.
# Look the key up by its alias; create the key + alias if it is absent so the
# script stays idempotent.
# ----------------------------------------------------------------------------
TF_STATE_KMS_KEY_ARN="$(
  aws kms describe-key \
    --key-id "${TF_STATE_KMS_ALIAS}" \
    --region "${AWS_REGION}" \
    --query 'KeyMetadata.Arn' \
    --output text 2>/dev/null || true
)"

if [ -z "${TF_STATE_KMS_KEY_ARN}" ] || [ "${TF_STATE_KMS_KEY_ARN}" = "None" ]; then

  TF_STATE_KMS_KEY_ID="$(
    aws kms create-key \
      --description "CMK for Terraform remote state bucket ${TF_STATE_BUCKET}" \
      --region "${AWS_REGION}" \
      --query 'KeyMetadata.KeyId' \
      --output text
  )"

  aws kms enable-key-rotation \
    --key-id "${TF_STATE_KMS_KEY_ID}" \
    --region "${AWS_REGION}"

  aws kms create-alias \
    --alias-name "${TF_STATE_KMS_ALIAS}" \
    --target-key-id "${TF_STATE_KMS_KEY_ID}" \
    --region "${AWS_REGION}"

  TF_STATE_KMS_KEY_ARN="$(
    aws kms describe-key \
      --key-id "${TF_STATE_KMS_ALIAS}" \
      --region "${AWS_REGION}" \
      --query 'KeyMetadata.Arn' \
      --output text
  )"

fi

# Encrypt the state bucket with the CMK (aws:kms) instead of SSE-S3 (AES256).
aws s3api put-bucket-encryption \
  --bucket "${TF_STATE_BUCKET}" \
  --server-side-encryption-configuration "{
    \"Rules\": [
      {
        \"ApplyServerSideEncryptionByDefault\": {
          \"SSEAlgorithm\": \"aws:kms\",
          \"KMSMasterKeyID\": \"${TF_STATE_KMS_KEY_ARN}\"
        },
        \"BucketKeyEnabled\": true
      }
    ]
  }"

# ----------------------------------------------------------------------------
# Enforce TLS-only access (deny any non-HTTPS request) via a bucket policy.
# ----------------------------------------------------------------------------
aws s3api put-bucket-policy \
  --bucket "${TF_STATE_BUCKET}" \
  --policy "{
    \"Version\": \"2012-10-17\",
    \"Statement\": [
      {
        \"Sid\": \"DenyInsecureTransport\",
        \"Effect\": \"Deny\",
        \"Principal\": \"*\",
        \"Action\": \"s3:*\",
        \"Resource\": [
          \"arn:aws:s3:::${TF_STATE_BUCKET}\",
          \"arn:aws:s3:::${TF_STATE_BUCKET}/*\"
        ],
        \"Condition\": {
          \"Bool\": {
            \"aws:SecureTransport\": \"false\"
          }
        }
      }
    ]
  }"

if ! aws dynamodb describe-table \
  --table-name "${TF_LOCK_TABLE}" \
  --region "${AWS_REGION}" \
  >/dev/null 2>&1
then

  aws dynamodb create-table \
    --table-name "${TF_LOCK_TABLE}" \
    --attribute-definitions \
      AttributeName=LockID,AttributeType=S \
    --key-schema \
      AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --sse-specification Enabled=true \
    --region "${AWS_REGION}"

  aws dynamodb wait table-exists \
    --table-name "${TF_LOCK_TABLE}" \
    --region "${AWS_REGION}"

fi

# Ensure server-side encryption is enabled on an already-existing lock table
# (idempotent — no-op if it is already AWS-owned/KMS encrypted).
aws dynamodb update-table \
  --table-name "${TF_LOCK_TABLE}" \
  --sse-specification Enabled=true \
  --region "${AWS_REGION}" \
  >/dev/null 2>&1 || true

echo "Terraform backend bootstrap completed"
