#!/bin/bash
# Deploy Grafana dashboards, datasources, and dashboard provider config to the cluster.
# Reads dashboard JSON directly from infrastructure/grafana/dashboards/ — no templating.
# Run after the cluster and Grafana pod are up.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

# shellcheck source=scripts/lib/env-aliases.sh
source "${ROOT_DIR}/scripts/lib/env-aliases.sh"

# Grafana is deployed in the application namespace, not the monitoring namespace
NS="${K8S_NAMESPACE:-video-processing}"
PROM_URL="${PROMETHEUS_DATASOURCE_URL:-http://prometheus-service:9090}"
PROM_NAME="${PROMETHEUS_DATASOURCE_NAME:-Prometheus}"

echo "Deploying Grafana configuration to namespace: ${NS}"

# ── 1. Dashboard provider ConfigMap ─────────────────────────────────────────
kubectl create configmap grafana-dashboard-provider \
  --namespace "${NS}" \
  --from-literal=dashboards.yaml="$(cat <<'PROVIDER'
apiVersion: 1
providers:
  - name: default
    orgId: 1
    folder: Video Processing
    type: file
    disableDeletion: false
    editable: true
    options:
      path: /var/lib/grafana/dashboards
PROVIDER
)" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "  ✓ Dashboard provider configmap applied"

# ── 2. Datasources ConfigMap ─────────────────────────────────────────────────
kubectl create configmap grafana-datasources \
  --namespace "${NS}" \
  --from-literal=datasources.yaml="$(cat <<DATASOURCE
apiVersion: 1
datasources:
  - name: ${PROM_NAME}
    type: prometheus
    access: proxy
    url: ${PROM_URL}
    isDefault: true
    jsonData:
      timeInterval: "30s"
DATASOURCE
)" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "  ✓ Datasources configmap applied (Prometheus → ${PROM_URL})"

# ── 3. Dashboards ConfigMap (direct from JSON files) ─────────────────────────
DASH_DIR="${ROOT_DIR}/infrastructure/grafana/dashboards"

kubectl create configmap grafana-dashboards \
  --namespace "${NS}" \
  --from-file="${DASH_DIR}/platform-overview-dashboard.json" \
  --from-file="${DASH_DIR}/rabbitmq-dashboard.json" \
  --from-file="${DASH_DIR}/keda-dashboard.json" \
  --from-file="${DASH_DIR}/kubernetes-dashboard.json" \
  --from-file="${DASH_DIR}/eks-dashboard.json" \
  --from-file="${DASH_DIR}/node-dashboard.json" \
  --from-file="${DASH_DIR}/pod-dashboard.json" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "  ✓ Dashboards configmap applied (7 dashboards)"

# ── 4. Restart Grafana so it picks up the new mounts ─────────────────────────
kubectl rollout restart deployment/grafana --namespace "${NS}"
kubectl rollout status  deployment/grafana --namespace "${NS}" --timeout=120s

echo ""
echo "✓ Grafana dashboards deployed successfully."
echo ""
echo "To view: kubectl port-forward svc/grafana-service 3000:3000 -n ${NS}"
echo "Then open: http://localhost:3000  (admin / your GRAFANA_ADMIN_PASSWORD)"
echo "Dashboards are under: Dashboards → Video Processing"
