#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/env-aliases.sh
source "${ROOT_DIR}/scripts/lib/env-aliases.sh"

bash "${ROOT_DIR}/scripts/render-helm-charts.sh" "${ROOT_DIR}/.rendered-helm"

HELM_DIR="${ROOT_DIR}/.rendered-helm/infrastructure/helm"
GLOBAL_VALUES="${HELM_DIR}/global-values.yaml"

echo "Deploying MongoDB Helm Chart..."

helm upgrade --install "${MONGODB_RELEASE_NAME}" \
  "${HELM_DIR}/mongodb" \
  --namespace "${DATABASE_NAMESPACE}" \
  --create-namespace \
  -f "${GLOBAL_VALUES}" \
  --wait --timeout 10m

echo "Deploying PostgreSQL Helm Chart..."

helm upgrade --install "${POSTGRESQL_RELEASE_NAME}" \
  "${HELM_DIR}/postgresql" \
  --namespace "${DATABASE_NAMESPACE}" \
  --create-namespace \
  -f "${GLOBAL_VALUES}" \
  --wait --timeout 10m

echo "Deploying RabbitMQ Helm Chart..."

helm upgrade --install "${RABBITMQ_RELEASE_NAME}" \
  "${HELM_DIR}/rabbitmq" \
  --namespace "${MESSAGING_NAMESPACE}" \
  --create-namespace \
  -f "${GLOBAL_VALUES}" \
  --wait --timeout 10m

echo "Helm deployments completed."