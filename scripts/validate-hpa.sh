#!/bin/bash
# Validate metrics-server and HPAs required for production autoscaling.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/env-aliases.sh
source "${ROOT_DIR}/scripts/lib/env-aliases.sh"

: "${K8S_NAMESPACE:?Missing K8S_NAMESPACE}"

echo "=== Metrics server ==="
kubectl get deployment metrics-server -n kube-system
kubectl top nodes

echo "=== Horizontal Pod Autoscalers ==="
kubectl get hpa -n "${K8S_NAMESPACE}"

missing=0
for hpa in auth-hpa converter-hpa gateway-hpa notification-hpa; do
  if ! kubectl get hpa "${hpa}" -n "${K8S_NAMESPACE}" >/dev/null 2>&1; then
    echo "ERROR: Missing HPA ${hpa}"
    missing=1
    continue
  fi
  targets="$(kubectl get hpa "${hpa}" -n "${K8S_NAMESPACE}" -o jsonpath='{.status.currentMetrics}')"
  if [ -z "${targets}" ] || [ "${targets}" = "null" ]; then
    echo "WARN: HPA ${hpa} has no current metrics yet"
  else
    echo "OK   HPA ${hpa} reporting metrics"
  fi
done

if [ "${missing}" -ne 0 ]; then
  exit 1
fi

kubectl top pods -n "${K8S_NAMESPACE}" || true
echo "HPA validation completed successfully."
