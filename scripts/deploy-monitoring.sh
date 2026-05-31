#!/bin/bash
# Deploy Prometheus and Grafana manifests rendered from the repo templates.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/env-aliases.sh
source "${ROOT_DIR}/scripts/lib/env-aliases.sh"

if [ "${DEPLOY_MONITORING_STACK:-true}" != "true" ]; then
  echo "Skipping monitoring stack (DEPLOY_MONITORING_STACK=${DEPLOY_MONITORING_STACK})"
  exit 0
fi

RENDERED="${ROOT_DIR}/.rendered-k8s/infrastructure/kubernetes/monitoring"

bash "${ROOT_DIR}/scripts/render-k8s-manifests.sh" "${ROOT_DIR}/.rendered-k8s"

kubectl create namespace "${MONITORING_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

grafana_secret_template="${ROOT_DIR}/infrastructure/kubernetes/monitoring/grafana-secret.yaml"
if [ -f "${grafana_secret_template}" ]; then
  envsubst < "${grafana_secret_template}" | kubectl apply -f -
fi

for manifest in prometheus-configmap.yaml prometheus.yaml grafana.yaml gateway-servicemonitor.yaml auth-servicemonitor.yaml converter-servicemonitor.yaml notification-servicemonitor.yaml; do
  if [ -f "${RENDERED}/${manifest}" ]; then
    kubectl apply -f "${RENDERED}/${manifest}"
  fi
done

kubectl get pods -n "${K8S_NAMESPACE}" -l 'app in (prometheus,grafana)' || true
echo "Monitoring stack deployed."
