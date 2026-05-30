#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/env-aliases.sh
source "${ROOT_DIR}/scripts/lib/env-aliases.sh"

: "${K8S_NAMESPACE:?Missing K8S_NAMESPACE}"
: "${DOCKER_USERNAME:?Missing DOCKER_USERNAME}"
: "${DOCKER_PASSWORD:?Missing DOCKER_PASSWORD}"

kubectl create namespace "${K8S_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

SECRET_NAME="${DOCKER_REGISTRY_SECRET_NAME:-docker-registry-secret}"
REGISTRY="${DOCKER_IMAGE_REGISTRY:-docker.io}"

kubectl create secret docker-registry "${SECRET_NAME}" \
  --docker-server="${REGISTRY}" \
  --docker-username="${DOCKER_USERNAME}" \
  --docker-password="${DOCKER_PASSWORD}" \
  --namespace="${K8S_NAMESPACE}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Docker registry secret ${SECRET_NAME} applied in ${K8S_NAMESPACE}"
