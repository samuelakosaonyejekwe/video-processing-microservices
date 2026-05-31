#!/bin/bash
# Apply rendered Kubernetes network policies for app, database, and messaging namespaces.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/env-aliases.sh
source "${ROOT_DIR}/scripts/lib/env-aliases.sh"

RENDERED="${ROOT_DIR}/.rendered-k8s/infrastructure/kubernetes/network-policies"

bash "${ROOT_DIR}/scripts/render-k8s-manifests.sh" "${ROOT_DIR}/.rendered-k8s"

if [ "${APPLY_NETWORK_POLICIES:-true}" != "true" ]; then
  echo "Skipping network policies (APPLY_NETWORK_POLICIES=${APPLY_NETWORK_POLICIES})"
  exit 0
fi

echo "Applying network policies..."

for policy in \
  default-deny.yaml \
  gateway-network-policy.yaml \
  auth-network-policy.yaml \
  converter-network-policy.yaml \
  notification-network-policy.yaml \
  frontend-network-policy.yaml \
  redis-network-policy.yaml; do
  if [ -f "${RENDERED}/${policy}" ]; then
    kubectl apply -f "${RENDERED}/${policy}"
  fi
done

if [ -f "${RENDERED}/postgres-network-policy.yaml" ]; then
  kubectl apply -f "${RENDERED}/postgres-network-policy.yaml"
fi

if [ -f "${RENDERED}/mongodb-network-policy.yaml" ]; then
  kubectl apply -f "${RENDERED}/mongodb-network-policy.yaml"
fi

if [ -f "${RENDERED}/rabbitmq-network-policy.yaml" ]; then
  kubectl apply -f "${RENDERED}/rabbitmq-network-policy.yaml"
fi

kubectl get networkpolicies -A
echo "Network policies applied."
