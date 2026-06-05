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

bash "${ROOT_DIR}/scripts/install-prometheus-operator-crds.sh"

RENDERED="${ROOT_DIR}/.rendered-k8s/infrastructure/kubernetes/monitoring"

bash "${ROOT_DIR}/scripts/render-k8s-manifests.sh" "${ROOT_DIR}/.rendered-k8s"

kubectl create namespace "${MONITORING_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

# Enforce strong Grafana admin credentials at the actual deploy point (env-aliases
# only warns, since it is sourced by many non-deploy scripts).
if [ "${APP_ENV:-development}" = "production" ]; then
  if [ "${GRAFANA_ADMIN_USER:-admin}" = "admin" ]; then
    echo "ERROR: GRAFANA_ADMIN_USER must not be 'admin' in production (set the GitHub Variable)." >&2
    exit 1
  fi
  if [ -z "${GRAFANA_ADMIN_PASSWORD:-}" ]; then
    echo "ERROR: GRAFANA_ADMIN_PASSWORD must be set in production (provide via GitHub Secrets)." >&2
    exit 1
  fi
fi

grafana_secret_template="${ROOT_DIR}/infrastructure/kubernetes/monitoring/grafana-secret.yaml"
if [ -f "${grafana_secret_template}" ]; then
  envsubst < "${grafana_secret_template}" | kubectl apply -f -
fi

for manifest in prometheus-configmap.yaml prometheus.yaml rabbitmq-metrics-service.yaml grafana-pvc.yaml grafana.yaml gateway-servicemonitor.yaml auth-servicemonitor.yaml converter-servicemonitor.yaml notification-servicemonitor.yaml; do
  if [ -f "${RENDERED}/${manifest}" ]; then
    case "${manifest}" in
      *servicemonitor.yaml)
        if ! kubectl get crd servicemonitors.monitoring.coreos.com >/dev/null 2>&1; then
          echo "Skipping ${manifest} (ServiceMonitor CRD not installed)."
          continue
        fi
        ;;
    esac
    kubectl apply -f "${RENDERED}/${manifest}"
  fi
done

# Grafana ingress (public ALB URL). Only applied when both the hostname and an
# ACM certificate are configured; otherwise Grafana stays internal-only and the
# ingress is skipped so an empty host/cert can never be applied to the ALB.
if [ -n "${GRAFANA_DOMAIN:-}" ] && [ -n "${GRAFANA_ACM_CERTIFICATE_ARN:-}" ]; then
  if [ -f "${RENDERED}/grafana-ingress.yaml" ]; then
    echo "Applying Grafana ingress for ${GRAFANA_DOMAIN}..."
    kubectl apply -f "${RENDERED}/grafana-ingress.yaml"
  fi
else
  echo "Skipping Grafana ingress (GRAFANA_DOMAIN / GRAFANA_ACM_CERTIFICATE_ARN not set)."
fi

kubectl get pods -n "${K8S_NAMESPACE}" -l 'app in (prometheus,grafana)' || true
echo "Monitoring stack deployed."
