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

if [ -n "${configured}" ] && [ "${configured}" != "https://api.your-domain.com" ]; then
  printf '%s' "${configured}"
  exit 0
fi

host=""
if kubectl get ingress "${ingress_name}" -n "${namespace}" >/dev/null 2>&1; then
  host="$(kubectl get ingress "${ingress_name}" -n "${namespace}" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"
fi

if [ -z "${host}" ]; then
  host="$(kubectl get svc "${service_name}" -n "${namespace}" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"
fi

if [ -n "${host}" ]; then
  printf 'https://%s' "${host}"
  exit 0
fi

echo "ERROR: Could not discover production API URL from ingress or service" >&2
exit 1
