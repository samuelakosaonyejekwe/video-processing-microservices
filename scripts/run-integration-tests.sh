#!/bin/bash
# Start the local stack and run integration/e2e tests against it.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

# shellcheck source=scripts/lib/env-aliases.sh
source "${ROOT_DIR}/scripts/lib/env-aliases.sh"

RUNTIME_ENV="${ROOT_DIR}/.env.compose.runtime"
if [ -f "${ROOT_DIR}/jwt-private.pem" ]; then
  grep -v '^JWT_PRIVATE_KEY=' "${ROOT_DIR}/.env" | grep -v '^JWT_PUBLIC_KEY=' | grep -v '^JWT_ALGORITHM=' > "${RUNTIME_ENV}" || cp "${ROOT_DIR}/.env" "${RUNTIME_ENV}"
else
  grep -v '^JWT_PRIVATE_KEY=' "${ROOT_DIR}/.env" 2>/dev/null | grep -v '^JWT_PUBLIC_KEY=' > "${RUNTIME_ENV}" || cp "${ROOT_DIR}/.env" "${RUNTIME_ENV}"
fi
echo "JWT_ALGORITHM=RS256" >> "${RUNTIME_ENV}"

SECRETS_DIR="${ROOT_DIR}/.compose-secrets"
mkdir -p "${SECRETS_DIR}"
if [ -f "${ROOT_DIR}/jwt-private.pem" ]; then
  cp "${ROOT_DIR}/jwt-private.pem" "${SECRETS_DIR}/"
  openssl rsa -in "${ROOT_DIR}/jwt-private.pem" -pubout -out "${SECRETS_DIR}/jwt-public.pem" 2>/dev/null || true
  chmod 644 "${SECRETS_DIR}/"*.pem
fi

export COMPOSE_ENV_FILE="${RUNTIME_ENV}"
export COMPOSE_SECRETS_DIR="${SECRETS_DIR}"

cleanup() {
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
