#!/bin/bash
# Install Prometheus Operator CRDs required for ServiceMonitor resources.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/env-aliases.sh
source "${ROOT_DIR}/scripts/lib/env-aliases.sh"

if kubectl get crd servicemonitors.monitoring.coreos.com >/dev/null 2>&1; then
  echo "Prometheus Operator CRDs already installed."
  exit 0
fi

echo "Installing Prometheus Operator CRDs..."
helm repo add prometheus-community "${PROMETHEUS_HELM_REPOSITORY:-https://prometheus-community.github.io/helm-charts}" 2>/dev/null || true
helm repo update prometheus-community

helm upgrade --install prometheus-operator-crds prometheus-community/prometheus-operator-crds \
  --namespace "${MONITORING_NAMESPACE}" \
  --create-namespace \
  --wait \
  --timeout "${DEPLOY_ROLLOUT_TIMEOUT:-120s}"

echo "Prometheus Operator CRDs installed."
