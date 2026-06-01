#!/bin/bash
# Print a reachable API base URL from ingress, load balancer, or port-forward fallback.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/env-aliases.sh
source "${ROOT_DIR}/scripts/lib/env-aliases.sh"

namespace="${K8S_NAMESPACE:-video-processing}"
ingress_name="${GATEWAY_INGRESS_NAME:-gateway-ingress}"
service_name="${GATEWAY_SERVICE_NAME:-gateway-service}"
configured="${API_BASE_URL:-}"
scheme="http"

if [[ "${ALB_LISTEN_PORTS:-}" == *"HTTPS"* ]] || [[ "${configured}" == https://* ]]; then
  scheme="https"
fi

if [ -n "${configured}" ] \
  && [ "${configured}" != "https://api.your-domain.com" ] \
  && [[ "${configured}" != *"localhost"* ]]; then
  printf '%s' "${configured}"
  exit 0
fi

host=""
if kubectl get ingress "${ingress_name}" -n "${namespace}" >/dev/null 2>&1; then
  host="$(kubectl get ingress "${ingress_name}" -n "${namespace}" -o jsonpath='{.spec.rules[0].host}' 2>/dev/null || true)"
  if [ -n "${host}" ]; then
    tls_host="$(kubectl get ingress "${ingress_name}" -n "${namespace}" -o jsonpath='{.spec.tls[0].hosts[0]}' 2>/dev/null || true)"
    listen_ports="$(kubectl get ingress "${ingress_name}" -n "${namespace}" -o jsonpath='{.metadata.annotations.alb\.ingress\.kubernetes\.io/listen-ports}' 2>/dev/null || true)"
    ssl_redirect="$(kubectl get ingress "${ingress_name}" -n "${namespace}" -o jsonpath='{.metadata.annotations.alb\.ingress\.kubernetes\.io/ssl-redirect}' 2>/dev/null || true)"

    if [ -n "${tls_host}" ] || [[ "${listen_ports}" == *"HTTPS"* ]] || [ -n "${ssl_redirect}" ]; then
      scheme="https"
    fi
  else
    host="$(kubectl get ingress "${ingress_name}" -n "${namespace}" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"
  fi
fi

if [ -z "${host}" ]; then
  host="$(kubectl get svc "${service_name}" -n "${namespace}" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"
fi

if [ -n "${host}" ]; then
  printf '%s://%s' "${scheme}" "${host}"
  exit 0
fi

echo "ERROR: Could not discover production API URL from ingress or service" >&2
exit 1
