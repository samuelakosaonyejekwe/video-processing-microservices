#!/bin/bash
# Install cert-manager (if needed) and issue internal service TLS certificates.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/env-aliases.sh
source "${ROOT_DIR}/scripts/lib/env-aliases.sh"

if [ "${DEPLOY_MTLS_STACK:-false}" != "true" ]; then
  echo "Skipping mTLS stack (DEPLOY_MTLS_STACK=${DEPLOY_MTLS_STACK:-false})"
  exit 0
fi

if ! kubectl get namespace cert-manager >/dev/null 2>&1; then
  echo "Installing cert-manager..."
  if kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.4/cert-manager.yaml; then
    kubectl wait --for=condition=Available deployment/cert-manager \
      -n cert-manager --timeout="${DEPLOY_ROLLOUT_TIMEOUT:-120s}" || true
    kubectl wait --for=condition=Available deployment/cert-manager-webhook \
      -n cert-manager --timeout="${DEPLOY_ROLLOUT_TIMEOUT:-120s}" || true
  else
    echo "WARNING: cert-manager install failed; skipping internal certificate issuance." >&2
    exit 0
  fi
fi

RENDERED="${ROOT_DIR}/.rendered-k8s/infrastructure/kubernetes/mtls"
bash "${ROOT_DIR}/scripts/render-k8s-manifests.sh" "${ROOT_DIR}/.rendered-k8s"

if [ -f "${RENDERED}/internal-ca-issuer.yaml" ]; then
  kubectl apply -f "${RENDERED}/internal-ca-issuer.yaml"
fi

if [ -f "${RENDERED}/service-certificates.yaml" ]; then
  kubectl apply -f "${RENDERED}/service-certificates.yaml"
fi

for cert in gateway-internal-tls auth-internal-tls converter-internal-tls notification-internal-tls; do
  if kubectl get certificate "${cert}" -n "${K8S_NAMESPACE}" >/dev/null 2>&1; then
    kubectl wait --for=condition=Ready "certificate/${cert}" \
      -n "${K8S_NAMESPACE}" \
      --timeout="${DEPLOY_JOB_WAIT_TIMEOUT:-120s}" || true
  fi
done

echo "Internal mTLS certificates issued (mount secrets in workloads when enabling INTERNAL_TLS)."
