#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/env-aliases.sh
source "${ROOT_DIR}/scripts/lib/env-aliases.sh"

if [ "${DEPLOY_MTLS_STACK:-false}" != "true" ]; then
  echo "Skipping mTLS validation (DEPLOY_MTLS_STACK=false)."
  exit 0
fi

missing=0
for cert in gateway-internal-tls auth-internal-tls converter-internal-tls notification-internal-tls; do
  if kubectl get certificate "${cert}" -n "${K8S_NAMESPACE}" >/dev/null 2>&1; then
    condition="$(kubectl get certificate "${cert}" -n "${K8S_NAMESPACE}" \
      -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)"
    if [ "${condition}" = "True" ]; then
      echo "OK   certificate/${cert} Ready=True"
    else
      echo "WARN certificate/${cert} not Ready (status=${condition:-unknown})" >&2
      missing=1
    fi
  else
    echo "WARN certificate/${cert} missing" >&2
    missing=1
  fi
done

if [ "${missing}" -ne 0 ]; then
  echo "mTLS validation completed with warnings (HTTP traffic remains active)." >&2
  exit 0
fi

echo "mTLS validation completed successfully."
