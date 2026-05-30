#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=scripts/lib/env-aliases.sh
source "${ROOT_DIR}/scripts/lib/env-aliases.sh"

if [ -f "${ROOT_DIR}/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  source "${ROOT_DIR}/.env"
  set +a
  # shellcheck source=scripts/lib/env-aliases.sh
  source "${ROOT_DIR}/scripts/lib/env-aliases.sh"
fi

if [ -z "${AWS_ACCOUNT_ID:-}" ] && command -v aws >/dev/null 2>&1; then
  export AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text 2>/dev/null || true)"
fi

bash "${ROOT_DIR}/scripts/render-k8s-manifests.sh" "${ROOT_DIR}/.rendered-k8s"

RENDERED="${ROOT_DIR}/.rendered-k8s/infrastructure/kubernetes"

kubectl apply -f "${RENDERED}/namespaces/"
kubectl apply -f "${RENDERED}/serviceaccounts/"
kubectl apply -f "${RENDERED}/secrets/"

# Deploy workloads first; full configmaps applied last so they are not overwritten.
for dir in gateway auth converter notification redis; do
  for kind in deployment service ingress hpa; do
    manifest="${RENDERED}/${dir}/${kind}.yaml"
    if [ -f "${manifest}" ]; then
      kubectl apply -f "${manifest}"
    fi
  done
done

if [ -d "${RENDERED}/configmaps" ]; then
  kubectl apply -f "${RENDERED}/configmaps/"
fi

echo "Microservices deployed successfully."
