#!/bin/bash
# Smoke test: build and start the full stack, verify health endpoints, tear down.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

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

# Prepare runtime env file with resolved defaults for compose
RUNTIME_ENV="${ROOT_DIR}/.env.compose.runtime"
: > "${RUNTIME_ENV}"
if [ -f "${ROOT_DIR}/.env" ]; then
  set +u
  set -a
  # shellcheck disable=SC1091
  source "${ROOT_DIR}/.env"
  set +a
  set -u
fi
# shellcheck source=scripts/lib/env-aliases.sh
source "${ROOT_DIR}/scripts/lib/env-aliases.sh"

write_env() {
  local key="$1"
  local value="${!key:-}"
  if [ -n "$value" ]; then
    printf '%s=%q\n' "$key" "$value" >> "${RUNTIME_ENV}"
  fi
}

for key in \
  APP_ENV POSTGRES_HOST POSTGRES_PORT POSTGRES_USER POSTGRES_PASSWORD POSTGRES_DB POSTGRES_SSL_MODE \
  RABBITMQ_PORT RABBITMQ_USERNAME RABBITMQ_PASSWORD RABBITMQ_DEFAULT_USER RABBITMQ_DEFAULT_PASS \
  JWT_ISSUER JWT_AUDIENCE JWT_ACTIVE_KID \
  GATEWAY_APP_PORT AUTH_APP_PORT CONVERTER_APP_PORT NOTIFICATION_APP_PORT \
  VIDEO_UPLOAD_QUEUE NOTIFICATION_QUEUE GATEWAY_EVENTS_QUEUE \
  MONGO_USERNAME MONGO_PASSWORD MONGO_DATABASE MONGO_PORT \
  AWS_REGION AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY \
  S3_UPLOAD_BUCKET S3_AUDIO_BUCKET SMTP_HOST SMTP_PORT SMTP_EMAIL SMTP_PASSWORD SMTP_FROM_EMAIL \
  CORS_ALLOWED_ORIGINS; do
  write_env "$key"
done

if [ -f "${ROOT_DIR}/jwt-private.pem" ]; then
  echo "JWT_ALGORITHM=RS256" >> "${RUNTIME_ENV}"
else
  write_env "JWT_ALGORITHM"
fi

if [ -f "${ROOT_DIR}/jwt-private.pem" ] && [ ! -f "${ROOT_DIR}/jwt-public.pem" ]; then
  openssl rsa -in "${ROOT_DIR}/jwt-private.pem" -pubout -out "${ROOT_DIR}/jwt-public.pem" 2>/dev/null || true
fi

SECRETS_DIR="${ROOT_DIR}/.compose-secrets"
mkdir -p "${SECRETS_DIR}"
if [ -f "${ROOT_DIR}/jwt-private.pem" ]; then
  cp "${ROOT_DIR}/jwt-private.pem" "${SECRETS_DIR}/"
  cp "${ROOT_DIR}/jwt-public.pem" "${SECRETS_DIR}/"
  chmod 644 "${SECRETS_DIR}/jwt-private.pem" "${SECRETS_DIR}/jwt-public.pem"
fi
export COMPOSE_SECRETS_DIR="${SECRETS_DIR}"

export COMPOSE_ENV_FILE="${RUNTIME_ENV}"
export APP_ENV="${APP_ENV:-development}"
export POSTGRES_SSL_MODE="${POSTGRES_SSL_MODE:-disable}"
export ENABLE_SWAGGER="${ENABLE_SWAGGER:-true}"

cleanup() {
  echo ""
  echo "=== Tearing down stack ==="
  docker compose --env-file "${COMPOSE_ENV_FILE}" down --remove-orphans 2>/dev/null || true
}

trap cleanup EXIT

echo "=== Building and starting stack ==="
docker compose --env-file "${COMPOSE_ENV_FILE}" up --build -d

echo "=== Waiting for infrastructure ==="
for i in $(seq 1 40); do
  if docker compose --env-file "${COMPOSE_ENV_FILE}" ps postgres 2>/dev/null | grep -q "(healthy)"; then
    echo "OK   postgres"
    break
  fi
  sleep 3
done

echo ""
echo "=== Waiting for services (max 180s) ==="

wait_for() {
  local name="$1"
  local url="$2"
  local max="${3:-60}"
  local i=0
  while [ "$i" -lt "$max" ]; do
    if curl -sf "$url" >/dev/null 2>&1; then
      echo "OK   $name"
      return 0
    fi
    sleep 3
    i=$((i + 3))
  done
  echo "FAIL $name ($url)"
  docker compose --env-file "${COMPOSE_ENV_FILE}" logs "$name" 2>&1 | tail -30
  return 1
}

wait_for gateway "http://localhost:${GATEWAY_APP_PORT:-8080}/health" 180
wait_for auth "http://localhost:${AUTH_APP_PORT:-8000}/health" 180
wait_for converter "http://localhost:${CONVERTER_APP_PORT:-8002}/health" 180
wait_for notification "http://localhost:${NOTIFICATION_APP_PORT:-8003}/health" 180

echo ""
echo "=== Health check responses ==="
curl -sf "http://localhost:${GATEWAY_APP_PORT:-8080}/health" && echo ""
curl -sf "http://localhost:${AUTH_APP_PORT:-8000}/health" && echo ""
curl -sf "http://localhost:${CONVERTER_APP_PORT:-8002}/health" && echo ""
curl -sf "http://localhost:${NOTIFICATION_APP_PORT:-8003}/health" && echo ""

echo ""
echo "=== Smoke test passed ==="
