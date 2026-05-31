#!/bin/bash
# Verify service images exist in ECR before deploying a specific tag.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/env-aliases.sh
source "${ROOT_DIR}/scripts/lib/env-aliases.sh"
# shellcheck source=scripts/resolve-ecr-registry.sh
source "${ROOT_DIR}/scripts/resolve-ecr-registry.sh"

: "${IMAGE_TAG:?Missing IMAGE_TAG}"
: "${AWS_REGION:?Missing AWS_REGION}"
: "${PROJECT_NAME:?Missing PROJECT_NAME}"

if [ -z "${AWS_ACCOUNT_ID:-}" ]; then
  AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
  export AWS_ACCOUNT_ID
fi

ECR_NAMESPACE="${ECR_IMAGE_NAMESPACE:-${PROJECT_NAME}}"
REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

services=(
  gateway-service
  auth-service
  converter-service
  notification-service
  frontend
)

missing=0
for service in "${services[@]}"; do
  repo="${ECR_NAMESPACE}/${service}"
  if aws ecr describe-images \
    --region "${AWS_REGION}" \
    --repository-name "${repo}" \
    --image-ids "imageTag=${IMAGE_TAG}" \
    >/dev/null 2>&1; then
    echo "ECR image found: ${REGISTRY}/${repo}:${IMAGE_TAG}"
  else
    echo "Missing ECR image: ${REGISTRY}/${repo}:${IMAGE_TAG}" >&2
    missing=1
  fi
done

if [ "${missing}" -ne 0 ]; then
  echo "Deploy aborted: build and push images for tag ${IMAGE_TAG} first." >&2
  exit 1
fi

echo "All service images present in ECR for tag ${IMAGE_TAG}."
