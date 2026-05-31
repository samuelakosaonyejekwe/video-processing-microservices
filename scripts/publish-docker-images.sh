#!/bin/bash
# Build service images and push to ECR (primary) and Docker Hub (mirror).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/env-aliases.sh
source "${ROOT_DIR}/scripts/lib/env-aliases.sh"

: "${DOCKER_USERNAME:?Missing DOCKER_USERNAME}"
: "${IMAGE_TAG:?Missing IMAGE_TAG}"
: "${AWS_REGION:?Missing AWS_REGION}"
: "${PROJECT_NAME:?Missing PROJECT_NAME}"

if [ -z "${AWS_ACCOUNT_ID:-}" ]; then
  AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
  export AWS_ACCOUNT_ID
fi

ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
ECR_NAMESPACE="${ECR_IMAGE_NAMESPACE:-${PROJECT_NAME}}"

aws ecr get-login-password --region "${AWS_REGION}" \
  | docker login --username AWS --password-stdin "${ECR_REGISTRY}"

services=(
  "gateway-service:services/gateway/Dockerfile"
  "auth-service:services/auth/Dockerfile"
  "converter-service:services/converter/Dockerfile"
  "notification-service:services/notification/Dockerfile"
  "frontend:services/frontend/Dockerfile"
)

for entry in "${services[@]}"; do
  service="${entry%%:*}"
  dockerfile="${entry#*:}"

  ecr_image="${ECR_REGISTRY}/${ECR_NAMESPACE}/${service}:${IMAGE_TAG}"
  ecr_latest="${ECR_REGISTRY}/${ECR_NAMESPACE}/${service}:latest"
  hub_image="${DOCKER_USERNAME}/${service}:${IMAGE_TAG}"
  hub_latest="${DOCKER_USERNAME}/${service}:latest"

  docker build \
    --pull \
    --no-cache \
    -t "${ecr_image}" \
    -t "${ecr_latest}" \
    -t "${hub_image}" \
    -t "${hub_latest}" \
    -f "${dockerfile}" "${ROOT_DIR}"

  docker push "${ecr_image}"
  docker push "${ecr_latest}"
  docker push "${hub_image}"
  docker push "${hub_latest}"

  echo "Published ${service} to ${ecr_latest} and ${hub_latest}"
done

echo "All images published to ECR (${ECR_REGISTRY}/${ECR_NAMESPACE}) and Docker Hub (${DOCKER_USERNAME})"
