#!/bin/bash
# Start the local stack and run integration/e2e tests against it.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

# shellcheck source=scripts/lib/prepare-compose-env.sh
source "${ROOT_DIR}/scripts/lib/prepare-compose-env.sh"
prepare_compose_env "${ROOT_DIR}"

cleanup() {
  if [ "${NO_CLEANUP:-}" = "1" ]; then
    return
  fi
  docker compose --env-file "${COMPOSE_ENV_FILE}" down --remove-orphans 2>/dev/null || true
}
trap cleanup EXIT

docker compose --env-file "${COMPOSE_ENV_FILE}" up -d --build

echo "=== Waiting for services ==="
for _ in $(seq 1 60); do
  if curl -sf http://localhost:8080/health >/dev/null 2>&1 \
    && curl -sf http://localhost:8000/health >/dev/null 2>&1 \
    && curl -sf http://localhost:8002/health >/dev/null 2>&1 \
    && curl -sf http://localhost:8003/health >/dev/null 2>&1; then
    break
  fi
  sleep 3
done

export INTEGRATION_TESTS=true
export GATEWAY_BASE_URL="${GATEWAY_BASE_URL:-http://localhost:8080}"
export AUTH_BASE_URL="${AUTH_BASE_URL:-http://localhost:8000}"
export CONVERTER_BASE_URL="${CONVERTER_BASE_URL:-http://localhost:8002}"
export NOTIFICATION_BASE_URL="${NOTIFICATION_BASE_URL:-http://localhost:8003}"

echo "=== Running integration and e2e tests ==="
python3 -m pytest tests/integration tests/e2e -v --tb=short

echo "=== Integration tests passed ==="
