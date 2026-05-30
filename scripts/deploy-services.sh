#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=scripts/lib/env-aliases.sh
source "${ROOT_DIR}/scripts/lib/env-aliases.sh"

if [ -f "${ROOT_DIR}/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  source "${ROOT_DIR}/.env"
  set +a
  # shellcheck source=scripts/lib/env-aliases.sh
  source "${ROOT_DIR}/scripts/lib/env-aliases.sh"
fi

bash "${ROOT_DIR}/scripts/render-k8s-manifests.sh" "${ROOT_DIR}/.rendered-k8s"

kubectl apply -f "${ROOT_DIR}/.rendered-k8s/infrastructure/kubernetes/namespaces/"
kubectl apply -f "${ROOT_DIR}/.rendered-k8s/infrastructure/kubernetes/secrets/"
kubectl apply -f "${ROOT_DIR}/.rendered-k8s/infrastructure/kubernetes/configmaps/"
kubectl apply -f "${ROOT_DIR}/.rendered-k8s/infrastructure/kubernetes/gateway/"
kubectl apply -f "${ROOT_DIR}/.rendered-k8s/infrastructure/kubernetes/auth/"
kubectl apply -f "${ROOT_DIR}/.rendered-k8s/infrastructure/kubernetes/converter/"
kubectl apply -f "${ROOT_DIR}/.rendered-k8s/infrastructure/kubernetes/notification/"
kubectl apply -f "${ROOT_DIR}/.rendered-k8s/infrastructure/kubernetes/redis/"

echo "Microservices deployed successfully."
