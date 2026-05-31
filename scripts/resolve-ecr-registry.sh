#!/bin/bash
# Point deploy image references at ECR when AWS credentials are available.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/env-aliases.sh
source "${ROOT_DIR}/scripts/lib/env-aliases.sh"

if [ "${USE_ECR_REGISTRY:-true}" != "true" ]; then
  exit 0
fi

if [ -z "${AWS_ACCOUNT_ID:-}" ] && command -v aws >/dev/null 2>&1; then
  AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text 2>/dev/null || true)"
  export AWS_ACCOUNT_ID
fi

if [ -z "${AWS_ACCOUNT_ID:-}" ] || [ -z "${AWS_REGION:-}" ]; then
  exit 0
fi

export DOCKER_IMAGE_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
export DOCKER_IMAGE_NAMESPACE="${ECR_IMAGE_NAMESPACE:-${DOCKER_IMAGE_NAMESPACE:-${PROJECT_NAME}}}"
export FRONTEND_IMAGE="${DOCKER_IMAGE_REGISTRY}/${DOCKER_IMAGE_NAMESPACE}/frontend:${IMAGE_TAG}"

echo "Using ECR registry: ${DOCKER_IMAGE_REGISTRY}/${DOCKER_IMAGE_NAMESPACE}"
