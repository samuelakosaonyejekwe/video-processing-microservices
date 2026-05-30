#!/bin/bash

set -euo pipefail

: "${AWS_REGION:?Missing AWS_REGION}"

: "${TF_STATE_BUCKET:?Missing TF_STATE_BUCKET}"

: "${TF_LOCK_TABLE:?Missing TF_LOCK_TABLE}"

: "${PROJECT_NAME:?Missing PROJECT_NAME}"

: "${APP_ENV:?Missing APP_ENV}"

cd infrastructure/terraform

terraform init \
  -backend-config="bucket=${TF_STATE_BUCKET}" \
  -backend-config="key=${PROJECT_NAME}/${APP_ENV}/terraform.tfstate" \
  -backend-config="region=${AWS_REGION}" \
  -backend-config="dynamodb_table=${TF_LOCK_TABLE}" \
  -backend-config="encrypt=true"