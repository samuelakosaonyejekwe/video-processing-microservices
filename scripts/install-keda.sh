#!/bin/bash
# Install or upgrade KEDA for queue-driven worker scaling.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/env-aliases.sh
source "${ROOT_DIR}/scripts/lib/env-aliases.sh"

: "${KEDA_NAMESPACE:?Missing KEDA_NAMESPACE}"
KEDA_RELEASE_NAME="${KEDA_RELEASE_NAME:-keda}"
KEDA_HELM_REPOSITORY="${KEDA_HELM_REPOSITORY:-https://kedacore.github.io/charts}"
KEDA_CHART_NAME="${KEDA_CHART_NAME:-keda}"
KEDA_INSTALL_TIMEOUT="${KEDA_INSTALL_TIMEOUT:-120s}"

# Install or upgrade KEDA. prometheus.operator.enabled=true exposes the operator's
# Prometheus metrics on port 8080 (scraped by Prometheus for the KEDA dashboard).
# Run helm even when the CRD already exists so the prometheus setting is applied
# on an existing cluster (idempotent; --reuse-values preserves other settings).
echo "Installing/upgrading KEDA Helm chart (prometheus operator metrics enabled)..."
helm repo add kedacore "${KEDA_HELM_REPOSITORY}" 2>/dev/null || true
helm repo update 2>/dev/null || true
if kubectl get crd scaledobjects.keda.sh >/dev/null 2>&1; then
  helm upgrade "${KEDA_RELEASE_NAME}" "kedacore/${KEDA_CHART_NAME}" \
    --namespace "${KEDA_NAMESPACE}" --reuse-values \
    --set prometheus.operator.enabled=true \
    --wait --timeout "${KEDA_INSTALL_TIMEOUT}" || echo "KEDA upgrade skipped/failed (non-fatal)."
else
  helm upgrade --install "${KEDA_RELEASE_NAME}" "kedacore/${KEDA_CHART_NAME}" \
    --namespace "${KEDA_NAMESPACE}" \
    --create-namespace \
    --set prometheus.operator.enabled=true \
    --wait \
    --timeout "${KEDA_INSTALL_TIMEOUT}"
fi

for deploy in keda-operator keda-metrics-apiserver; do
  if kubectl get "deployment/${deploy}" -n "${KEDA_NAMESPACE}" >/dev/null 2>&1; then
    kubectl rollout status "deployment/${deploy}" \
      -n "${KEDA_NAMESPACE}" \
      --timeout="${KEDA_INSTALL_TIMEOUT}"
  fi
done

echo "KEDA is ready."
