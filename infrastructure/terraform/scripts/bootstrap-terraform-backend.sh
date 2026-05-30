#!/bin/bash

set -euo pipefail

: "${AWS_REGION:?Missing AWS_REGION}"

: "${TF_STATE_BUCKET:?Missing TF_STATE_BUCKET}"

: "${TF_LOCK_TABLE:?Missing TF_LOCK_TABLE}"

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

aws s3api put-bucket-encryption \
  --bucket "${TF_STATE_BUCKET}" \
  --server-side-encryption-configuration '{
    "Rules": [
      {
        "ApplyServerSideEncryptionByDefault": {
          "SSEAlgorithm": "AES256"
        }
      }
    ]
  }'

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
    --region "${AWS_REGION}"

fi

echo "Terraform backend bootstrap completed"