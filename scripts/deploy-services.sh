#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=scripts/lib/env-aliases.sh
source "${ROOT_DIR}/scripts/lib/env-aliases.sh"

if [ -f "${ROOT_DIR}/.env" ]; then
  set +u
  set -a
  # shellcheck disable=SC1091
  source "${ROOT_DIR}/.env"
  set +a
  set -u
  # shellcheck source=scripts/lib/env-aliases.sh
  source "${ROOT_DIR}/scripts/lib/env-aliases.sh"
fi

if [ -z "${AWS_ACCOUNT_ID:-}" ] && command -v aws >/dev/null 2>&1; then
  export AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text 2>/dev/null || true)"
fi

# shellcheck source=scripts/resolve-ecr-registry.sh
source "${ROOT_DIR}/scripts/resolve-ecr-registry.sh"

bash "${ROOT_DIR}/scripts/render-k8s-manifests.sh" "${ROOT_DIR}/.rendered-k8s"

RENDERED="${ROOT_DIR}/.rendered-k8s/infrastructure/kubernetes"

kubectl apply -f "${RENDERED}/namespaces/"
kubectl apply -f "${RENDERED}/serviceaccounts/"
kubectl apply -f "${RENDERED}/secrets/"

bash "${ROOT_DIR}/scripts/sync-rabbitmq-credentials.sh"
bash "${ROOT_DIR}/scripts/sync-postgres-password.sh"

if [ -d "${RENDERED}/configmaps" ]; then
  kubectl apply -f "${RENDERED}/configmaps/"
fi

# Deploy workloads after configmaps so pods can mount required config.
for dir in gateway auth converter notification redis frontend; do
  for kind in deployment service ingress hpa; do
    manifest="${RENDERED}/${dir}/${kind}.yaml"
    if [ -f "${manifest}" ]; then
      kubectl apply -f "${manifest}"
    fi
  done
done

if [ "${APPLY_NETWORK_POLICIES:-true}" = "true" ]; then
  bash "${ROOT_DIR}/scripts/deploy-network-policies.sh"
fi

if [ "${DEPLOY_MONITORING_STACK:-true}" = "true" ]; then
  bash "${ROOT_DIR}/scripts/deploy-monitoring.sh"
fi

echo "Microservices deployed successfully."
