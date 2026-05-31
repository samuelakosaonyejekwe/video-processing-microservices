#!/bin/bash
# Verify dedicated queue worker deployments are healthy (one consumer each).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/env-aliases.sh
source "${ROOT_DIR}/scripts/lib/env-aliases.sh"

: "${K8S_NAMESPACE:?Missing K8S_NAMESPACE}"

workers=(
  gateway-worker
  converter-worker
  notification-worker
)

echo "=== Queue worker deployments ==="
missing=0
for worker in "${workers[@]}"; do
  if ! kubectl get "deployment/${worker}" -n "${K8S_NAMESPACE}" >/dev/null 2>&1; then
    echo "ERROR: Missing worker deployment ${worker}"
    missing=1
    continue
  fi

  ready="$(kubectl get "deployment/${worker}" -n "${K8S_NAMESPACE}" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)"
  desired="$(kubectl get "deployment/${worker}" -n "${K8S_NAMESPACE}" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo 1)"

  if [ "${ready:-0}" -lt "${desired:-1}" ]; then
    echo "ERROR: ${worker} ready=${ready:-0}/${desired:-1}"
    missing=1
    continue
  fi

  echo "OK   ${worker} ready=${ready}/${desired}"
done

if [ "${missing}" -ne 0 ]; then
  exit 1
fi

echo "Queue worker validation completed successfully."
