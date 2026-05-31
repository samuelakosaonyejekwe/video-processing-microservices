#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/env-aliases.sh
source "${ROOT_DIR}/scripts/lib/env-aliases.sh"

if [ "${DEPLOY_TRACING_STACK:-false}" != "true" ]; then
  echo "Skipping tracing stack (DEPLOY_TRACING_STACK=${DEPLOY_TRACING_STACK:-false})"
  exit 0
fi

RENDERED="${ROOT_DIR}/.rendered-k8s/infrastructure/kubernetes/tracing"
bash "${ROOT_DIR}/scripts/render-k8s-manifests.sh" "${ROOT_DIR}/.rendered-k8s"

if [ -f "${RENDERED}/tracing-namespace.yaml" ]; then
  kubectl apply -f "${RENDERED}/tracing-namespace.yaml"
fi

if [ -f "${RENDERED}/otel-collector.yaml" ]; then
  kubectl apply -f "${RENDERED}/otel-collector.yaml"
  kubectl rollout status deployment/otel-collector \
    -n "${TRACING_NAMESPACE}" \
    --timeout="${DEPLOY_ROLLOUT_TIMEOUT:-120s}"
fi

echo "Tracing stack deployed."
