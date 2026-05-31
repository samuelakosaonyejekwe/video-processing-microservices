#!/bin/bash
# Verify gateway pods can reach the auth service in-cluster.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/env-aliases.sh
source "${ROOT_DIR}/scripts/lib/env-aliases.sh"

if ! kubectl get deployment/auth-service -n "${K8S_NAMESPACE}" >/dev/null 2>&1; then
  echo "Skipping gateway-auth connectivity check (auth deployment missing)."
  exit 0
fi

echo "Waiting for auth-service rollout before connectivity checks..."
kubectl rollout status deployment/auth-service \
  -n "${K8S_NAMESPACE}" \
  --timeout="${DEPLOY_ROLLOUT_TIMEOUT:-120s}"

if ! kubectl get deployment/gateway-deployment -n "${K8S_NAMESPACE}" >/dev/null 2>&1; then
  echo "Skipping gateway-auth connectivity check (gateway deployment missing)."
  exit 0
fi

kubectl rollout status deployment/gateway-deployment \
  -n "${K8S_NAMESPACE}" \
  --timeout="${DEPLOY_ROLLOUT_TIMEOUT:-120s}"

gateway_pod="$(kubectl get pods -n "${K8S_NAMESPACE}" -l app=gateway \
  --field-selector=status.phase=Running \
  -o jsonpath='{range .items[?(@.status.containerStatuses[0].ready==true)]}{.metadata.name}{"\n"}{end}' \
  2>/dev/null | head -n1 || true)"

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
else
  echo "ERROR: Gateway cannot reach auth at ${health_url}" >&2
  exit 1
fi

auth_jwt_url="${auth_url%/}/health/jwt"
echo "Checking auth JWT signing at ${auth_jwt_url}"
jwt_health="$(kubectl exec -n "${K8S_NAMESPACE}" "${gateway_pod}" -- \
  sh -c "curl -sS --max-time 10 -w ' HTTP_STATUS:%{http_code}' '${auth_jwt_url}'" 2>&1 || true)"
jwt_status="$(printf '%s' "${jwt_health}" | sed -n 's/.* HTTP_STATUS:\([0-9][0-9][0-9]\)$/\1/p')"
jwt_body="$(printf '%s' "${jwt_health}" | sed 's/ HTTP_STATUS:[0-9][0-9][0-9]$//')"
if [ -z "${jwt_status}" ] || [ "${jwt_status}" != "200" ]; then
  echo "ERROR: Auth JWT health endpoint unavailable at ${auth_jwt_url} (status=${jwt_status:-unknown})" >&2
  if [ -n "${jwt_body}" ]; then
    echo "Response: ${jwt_body}" >&2
  fi
  exit 1
fi
if ! printf '%s' "${jwt_body}" | grep -q '"signing_ok"[[:space:]]*:[[:space:]]*true'; then
  echo "ERROR: Auth JWT signing check failed: ${jwt_body}" >&2
  exit 1
fi
echo "Auth JWT signing OK."
