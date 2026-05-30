#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/env-aliases.sh
source "${ROOT_DIR}/scripts/lib/env-aliases.sh"

bash "${ROOT_DIR}/scripts/render-helm-charts.sh" "${ROOT_DIR}/.rendered-helm"

HELM_DIR="${ROOT_DIR}/.rendered-helm/infrastructure/helm"
GLOBAL_VALUES="${HELM_DIR}/global-values.yaml"

recycle_failed_pods() {
  local namespace="$1"
  local failed_pods
  failed_pods="$(kubectl get pods -n "${namespace}" --field-selector=status.phase=Failed -o name 2>/dev/null || true)"
  if [ -n "${failed_pods}" ]; then
    echo "Recycling failed pods in ${namespace} before Helm upgrade..."
    kubectl delete ${failed_pods} -n "${namespace}" --wait=false || true
    sleep 5
  fi
}

echo "Deploying MongoDB Helm Chart..."

recycle_failed_pods "${DATABASE_NAMESPACE}"

helm upgrade --install "${MONGODB_RELEASE_NAME}" \
  "${HELM_DIR}/mongodb" \
  --namespace "${DATABASE_NAMESPACE}" \
  --create-namespace \
  -f "${GLOBAL_VALUES}" \
  --wait --timeout 20m

echo "Deploying PostgreSQL Helm Chart..."

recycle_failed_pods "${DATABASE_NAMESPACE}"

helm upgrade --install "${POSTGRESQL_RELEASE_NAME}" \
  "${HELM_DIR}/postgresql" \
  --namespace "${DATABASE_NAMESPACE}" \
  --create-namespace \
  -f "${GLOBAL_VALUES}" \
  --wait --timeout 20m

echo "Deploying RabbitMQ Helm Chart..."

recycle_failed_pods "${MESSAGING_NAMESPACE}"

helm upgrade --install "${RABBITMQ_RELEASE_NAME}" \
  "${HELM_DIR}/rabbitmq" \
  --namespace "${MESSAGING_NAMESPACE}" \
  --create-namespace \
  -f "${GLOBAL_VALUES}" \
  --wait --timeout 20m

echo "Helm deployments completed."