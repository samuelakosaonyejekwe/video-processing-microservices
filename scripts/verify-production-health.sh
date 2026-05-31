#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/env-aliases.sh
source "${ROOT_DIR}/scripts/lib/env-aliases.sh"

echo "=== Production health verification ==="
bash "${ROOT_DIR}/scripts/verify-deployment.sh"
bash "${ROOT_DIR}/scripts/validate-hpa.sh"
bash "${ROOT_DIR}/scripts/validate-keda.sh"
bash "${ROOT_DIR}/scripts/validate-queue-workers.sh"
bash "${ROOT_DIR}/scripts/validate-mtls.sh"
bash "${ROOT_DIR}/scripts/verify-gateway-auth-connectivity.sh"

if [ -n "${API_BASE_URL:-}" ]; then
  curl -fsS "${API_BASE_URL%/}/health" >/dev/null
  echo "API health OK: ${API_BASE_URL%/}/health"
fi

echo "Production health verification completed."
