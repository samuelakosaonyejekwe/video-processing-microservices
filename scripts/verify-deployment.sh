#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/env-aliases.sh
source "${ROOT_DIR}/scripts/lib/env-aliases.sh"

kubectl get pods -A

kubectl get deployments -A

kubectl get services -A

kubectl rollout status deployment/gateway-deployment \
  -n "${K8S_NAMESPACE}" --timeout=600s

for deploy in auth-service converter-service notification-deployment; do
  kubectl rollout status "deployment/${deploy}" -n "${K8S_NAMESPACE}" --timeout=600s
done
