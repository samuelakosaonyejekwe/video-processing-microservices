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
  echo "Recycling database pods in ${namespace} before Helm upgrade..."
  kubectl delete pod -n "${namespace}" -l app=mongodb --ignore-not-found --wait=false 2>/dev/null || true
  kubectl delete pod -n "${namespace}" -l app=postgresql --ignore-not-found --wait=false 2>/dev/null || true
  kubectl delete pod -n "${namespace}" -l app=rabbitmq --ignore-not-found --wait=false 2>/dev/null || true
  kubectl delete pod -n "${namespace}" --field-selector=status.phase=Failed --ignore-not-found --wait=false 2>/dev/null || true
  sleep 5
}

deploy_chart() {
  local release="$1"
  local chart_path="$2"
  local namespace="$3"
  helm upgrade --install "${release}" "${chart_path}" \
    --namespace "${namespace}" \
    --create-namespace \
    -f "${GLOBAL_VALUES}" \
    --wait=false
  recycle_failed_pods "${namespace}"
  kubectl rollout status "statefulset/${release}" -n "${namespace}" --timeout=1200s
}

echo "Deploying MongoDB Helm Chart..."

deploy_chart "${MONGODB_RELEASE_NAME}" "${HELM_DIR}/mongodb" "${DATABASE_NAMESPACE}"

echo "Deploying PostgreSQL Helm Chart..."

deploy_chart "${POSTGRESQL_RELEASE_NAME}" "${HELM_DIR}/postgresql" "${DATABASE_NAMESPACE}"

echo "Deploying RabbitMQ Helm Chart..."

deploy_chart "${RABBITMQ_RELEASE_NAME}" "${HELM_DIR}/rabbitmq" "${MESSAGING_NAMESPACE}"

echo "Helm deployments completed."