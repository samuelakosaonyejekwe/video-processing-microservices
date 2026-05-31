#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/env-aliases.sh
source "${ROOT_DIR}/scripts/lib/env-aliases.sh"
# shellcheck source=scripts/lib/k8s-pvc-cleanup.sh
source "${ROOT_DIR}/scripts/lib/k8s-pvc-cleanup.sh"

bash "${ROOT_DIR}/scripts/render-helm-charts.sh" "${ROOT_DIR}/.rendered-helm"

HELM_DIR="${ROOT_DIR}/.rendered-helm/infrastructure/helm"
GLOBAL_VALUES="${HELM_DIR}/global-values.yaml"

reset_unhealthy_release() {
  local release="$1"
  local namespace="$2"

  if ! kubectl get "statefulset/${release}" -n "${namespace}" >/dev/null 2>&1; then
    return 0
  fi

  if kubectl get "statefulset/${release}" -n "${namespace}" -o jsonpath='{.status.readyReplicas}' 2>/dev/null | grep -q '^1$'; then
    return 0
  fi

  echo "Resetting unhealthy ${release} in ${namespace} before Helm upgrade..."
  kubectl delete pod "${release}-0" -n "${namespace}" --ignore-not-found --wait=false 2>/dev/null || true

  if [ "${release}" = "mongodb" ]; then
    echo "MongoDB release unhealthy; restarting pod without deleting PVC..."
  fi
}

deploy_chart() {
  local release="$1"
  local chart_path="$2"
  local namespace="$3"

  reset_unhealthy_release "${release}" "${namespace}"

  if [ "${release}" = "mongodb" ]; then
    if kubectl get pvc mongodb-pvc -n "${namespace}" >/dev/null 2>&1; then
      if kubectl get pvc mongodb-pvc -n "${namespace}" -o jsonpath='{.metadata.deletionTimestamp}' 2>/dev/null | grep -q .; then
        wait_for_pvc_removal mongodb-pvc "${namespace}" 300
      fi
    fi
    prepare_mongodb_storage_for_helm "${namespace}"

    helm upgrade --install "${release}" "${chart_path}" \
      --namespace "${namespace}" \
      --create-namespace \
      -f "${GLOBAL_VALUES}" \
      --timeout 20m

    finalize_mongodb_storage_after_helm "${namespace}"
    return 0
  fi

  helm upgrade --install "${release}" "${chart_path}" \
    --namespace "${namespace}" \
    --create-namespace \
    -f "${GLOBAL_VALUES}" \
    --wait --timeout 20m
}

echo "Deploying MongoDB Helm Chart..."
deploy_chart "${MONGODB_RELEASE_NAME}" "${HELM_DIR}/mongodb" "${DATABASE_NAMESPACE}"

echo "Deploying PostgreSQL Helm Chart..."
deploy_chart "${POSTGRESQL_RELEASE_NAME}" "${HELM_DIR}/postgresql" "${DATABASE_NAMESPACE}"

echo "Deploying RabbitMQ Helm Chart..."
deploy_chart "${RABBITMQ_RELEASE_NAME}" "${HELM_DIR}/rabbitmq" "${MESSAGING_NAMESPACE}"

echo "Helm deployments completed."
