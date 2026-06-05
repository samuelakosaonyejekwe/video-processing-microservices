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
# PINNED chart version. Do NOT float to latest: chart 2.20.0 (with an upgrade)
# dropped the keda-operator-metrics-apiserver, breaking the HPA metric path and
# all ScaledObjects. 2.19.0 is the known-good version for this cluster.
KEDA_CHART_VERSION="${KEDA_CHART_VERSION:-2.19.0}"
KEDA_INSTALL_TIMEOUT="${KEDA_INSTALL_TIMEOUT:-120s}"

# Install or upgrade KEDA at the pinned version, with chart defaults (which include
# the metrics-apiserver) plus prometheus.operator.enabled=true (exposes operator
# Prometheus metrics on port 8080 for the KEDA dashboard). NOT --reuse-values: we
# want deterministic chart defaults so the metrics-apiserver is always present.
echo "Installing/upgrading KEDA Helm chart ${KEDA_CHART_VERSION} (prometheus operator metrics enabled)..."
helm repo add kedacore "${KEDA_HELM_REPOSITORY}" 2>/dev/null || true
helm repo update 2>/dev/null || true
helm upgrade --install "${KEDA_RELEASE_NAME}" "kedacore/${KEDA_CHART_NAME}" \
  --version "${KEDA_CHART_VERSION}" \
  --namespace "${KEDA_NAMESPACE}" \
  --create-namespace \
  --set prometheus.operator.enabled=true \
  --wait \
  --timeout "${KEDA_INSTALL_TIMEOUT}"

for deploy in keda-operator keda-metrics-apiserver; do
  if kubectl get "deployment/${deploy}" -n "${KEDA_NAMESPACE}" >/dev/null 2>&1; then
    kubectl rollout status "deployment/${deploy}" \
      -n "${KEDA_NAMESPACE}" \
      --timeout="${KEDA_INSTALL_TIMEOUT}"
  fi
done

echo "KEDA is ready."
