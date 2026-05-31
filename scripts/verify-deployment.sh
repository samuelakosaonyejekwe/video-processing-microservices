#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/env-aliases.sh
source "${ROOT_DIR}/scripts/lib/env-aliases.sh"

ROLLOUT_TIMEOUT="${DEPLOY_ROLLOUT_TIMEOUT:-120s}"
WORKER_ROLLOUT_TIMEOUT="${WORKER_ROLLOUT_TIMEOUT:-120s}"

if [ "${FORCE_ROLLOUT_RESTART:-false}" = "true" ]; then
  echo "Restarting microservice deployments (FORCE_ROLLOUT_RESTART=true)..."
  for deploy in gateway-deployment gateway-worker auth-service converter-service converter-worker notification-deployment notification-worker frontend-deployment; do
    if kubectl get "deployment/${deploy}" -n "${K8S_NAMESPACE}" >/dev/null 2>&1; then
      kubectl rollout restart "deployment/${deploy}" -n "${K8S_NAMESPACE}"
    fi
  done
else
  echo "Checking rollout status without forced restarts..."
fi

kubectl get pods -n "${K8S_NAMESPACE}"

critical_deployments=(
  gateway-deployment
  auth-service
  converter-service
  notification-deployment
  frontend-deployment
)

worker_deployments=(
  gateway-worker
  converter-worker
  notification-worker
)

for deploy in "${critical_deployments[@]}"; do
  if kubectl get "deployment/${deploy}" -n "${K8S_NAMESPACE}" >/dev/null 2>&1; then
    kubectl rollout status "deployment/${deploy}" -n "${K8S_NAMESPACE}" --timeout="${ROLLOUT_TIMEOUT}"
  fi
done

for deploy in "${worker_deployments[@]}"; do
  if kubectl get "deployment/${deploy}" -n "${K8S_NAMESPACE}" >/dev/null 2>&1; then
    kubectl rollout status "deployment/${deploy}" -n "${K8S_NAMESPACE}" --timeout="${WORKER_ROLLOUT_TIMEOUT}"
  fi
done
