#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/env-aliases.sh
source "${ROOT_DIR}/scripts/lib/env-aliases.sh"

echo "Restarting microservice deployments to pick up secret and config changes..."
for deploy in gateway-deployment gateway-worker auth-service converter-service converter-worker notification-deployment notification-worker frontend-deployment; do
  if kubectl get "deployment/${deploy}" -n "${K8S_NAMESPACE}" >/dev/null 2>&1; then
    kubectl rollout restart "deployment/${deploy}" -n "${K8S_NAMESPACE}"
  fi
done

kubectl get pods -A

kubectl get deployments -A

kubectl get services -A

kubectl rollout status deployment/gateway-deployment \
  -n "${K8S_NAMESPACE}" --timeout=600s

for deploy in gateway-worker auth-service converter-service converter-worker notification-deployment notification-worker frontend-deployment; do
  if kubectl get "deployment/${deploy}" -n "${K8S_NAMESPACE}" >/dev/null 2>&1; then
    kubectl rollout status "deployment/${deploy}" -n "${K8S_NAMESPACE}" --timeout=600s
  fi
done
