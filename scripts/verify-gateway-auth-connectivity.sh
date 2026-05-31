#!/bin/bash
# Verify gateway pods can reach the auth service in-cluster.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/env-aliases.sh
source "${ROOT_DIR}/scripts/lib/env-aliases.sh"

if ! kubectl get deployment/gateway-deployment -n "${K8S_NAMESPACE}" >/dev/null 2>&1; then
  echo "Skipping gateway-auth connectivity check (gateway deployment missing)."
  exit 0
fi

gateway_pod="$(kubectl get pods -n "${K8S_NAMESPACE}" -l app=gateway \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"

if [ -z "${gateway_pod}" ]; then
  echo "ERROR: No gateway pod found for auth connectivity check." >&2
  exit 1
fi

auth_url="${JWT_AUTH_SERVICE_URL:-http://auth-service.${K8S_NAMESPACE}.svc.cluster.local:${AUTH_K8S_SERVICE_PORT}}"
health_url="${auth_url%/}/health"

echo "Checking auth connectivity from pod/${gateway_pod} -> ${health_url}"

if kubectl exec -n "${K8S_NAMESPACE}" "${gateway_pod}" -- \
  curl -sf --max-time 10 "${health_url}" >/dev/null; then
  echo "Gateway -> auth connectivity OK."
  exit 0
fi

echo "ERROR: Gateway cannot reach auth at ${health_url}" >&2
kubectl exec -n "${K8S_NAMESPACE}" "${gateway_pod}" -- \
  curl -sv --max-time 10 "${health_url}" 2>&1 | tail -20 || true
exit 1
