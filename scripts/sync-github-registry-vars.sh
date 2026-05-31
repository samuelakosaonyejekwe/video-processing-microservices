#!/bin/bash
# Align GitHub Actions registry variables with ECR (single source of truth for deploy).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! gh auth status >/dev/null 2>&1; then
  echo "ERROR: gh CLI not authenticated. Run: gh auth login"
  exit 1
fi

# shellcheck source=scripts/lib/env-aliases.sh
source "${ROOT_DIR}/scripts/lib/env-aliases.sh"

if [ -f "${ROOT_DIR}/.env" ]; then
  set +u
  set -a
  # shellcheck disable=SC1091
  source "${ROOT_DIR}/.env"
  set +a
  set -u
  # shellcheck source=scripts/lib/env-aliases.sh
  source "${ROOT_DIR}/scripts/lib/env-aliases.sh"
fi

if [ -z "${AWS_ACCOUNT_ID:-}" ] && command -v aws >/dev/null 2>&1; then
  AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text 2>/dev/null || true)"
  export AWS_ACCOUNT_ID
fi

# shellcheck source=scripts/resolve-ecr-registry.sh
source "${ROOT_DIR}/scripts/resolve-ecr-registry.sh"

if [[ "${DOCKER_IMAGE_REGISTRY:-}" != *".amazonaws.com"* ]]; then
  echo "ERROR: Could not resolve ECR registry (need AWS_ACCOUNT_ID and AWS_REGION)."
  exit 1
fi

ECR_REPOSITORIES='["gateway-service","auth-service","converter-service","notification-service","frontend"]'

sync_var() {
  local name="$1"
  local value="$2"
  gh variable set "$name" --body "$value"
  echo "SYNC var ${name}=${value}"
}

echo "=== Syncing GitHub registry variables to ECR ==="
sync_var "DOCKER_IMAGE_REGISTRY" "${DOCKER_IMAGE_REGISTRY}"
sync_var "DOCKER_IMAGE_NAMESPACE" "${DOCKER_IMAGE_NAMESPACE}"
sync_var "DOCKER_REGISTRY" "${DOCKER_IMAGE_REGISTRY}"
sync_var "DOCKER_REPO_URL" "${DOCKER_IMAGE_REGISTRY}/${DOCKER_IMAGE_NAMESPACE}"
sync_var "FRONTEND_IMAGE" "${FRONTEND_IMAGE}"
sync_var "ECR_REPOSITORIES" "${ECR_REPOSITORIES}"
sync_var "DOCKER_REGISTRY_SECRET_NAME" "${DOCKER_REGISTRY_SECRET_NAME:-docker-registry-secret}"
sync_var "USE_ECR_REGISTRY" "true"

echo "Done. Registry vars now point at ECR."
