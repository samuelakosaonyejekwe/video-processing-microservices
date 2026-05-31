#!/bin/bash
# Build service images and push to ECR. Docker Hub mirror is optional.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/env-aliases.sh
source "${ROOT_DIR}/scripts/lib/env-aliases.sh"

: "${IMAGE_TAG:?Missing IMAGE_TAG}"
: "${AWS_REGION:?Missing AWS_REGION}"
: "${PROJECT_NAME:?Missing PROJECT_NAME}"

PUSH_DOCKER_HUB="${PUSH_DOCKER_HUB:-false}"
if [ "${PUSH_DOCKER_HUB}" = "true" ]; then
  : "${DOCKER_USERNAME:?Missing DOCKER_USERNAME (required when PUSH_DOCKER_HUB=true)}"
  : "${DOCKER_PASSWORD:?Missing DOCKER_PASSWORD (required when PUSH_DOCKER_HUB=true)}"
fi

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

  build_tags=(-t "${ecr_image}" -t "${ecr_latest}")
  if [ "${PUSH_DOCKER_HUB}" = "true" ]; then
    build_tags+=(
      -t "${DOCKER_USERNAME}/${service}:${IMAGE_TAG}"
      -t "${DOCKER_USERNAME}/${service}:latest"
    )
  fi

  docker build \
    --pull \
    --no-cache \
    "${build_tags[@]}" \
    -f "${dockerfile}" "${ROOT_DIR}"

  docker push "${ecr_image}"
  docker push "${ecr_latest}"

  if [ "${PUSH_DOCKER_HUB}" = "true" ]; then
    docker push "${DOCKER_USERNAME}/${service}:${IMAGE_TAG}"
    docker push "${DOCKER_USERNAME}/${service}:latest"
    echo "Published ${service} to ${ecr_latest} and Docker Hub"
  else
    echo "Published ${service} to ${ecr_latest}"
  fi
done

if [ "${PUSH_DOCKER_HUB}" = "true" ]; then
  echo "All images published to ECR (${ECR_REGISTRY}/${ECR_NAMESPACE}) and Docker Hub (${DOCKER_USERNAME})"
else
  echo "All images published to ECR (${ECR_REGISTRY}/${ECR_NAMESPACE})"
fi
