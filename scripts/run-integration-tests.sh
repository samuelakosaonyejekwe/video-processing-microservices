#!/bin/bash
# Start the local stack and run integration/e2e tests against it.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

# Integration tests run against a local docker-compose stack, not production.
# All services in the stack MUST share the same credentials; use explicit CI
# dev values so containers and service configs are guaranteed to match.
# These are NOT production secrets — they exist only within the ephemeral CI
# runner network.
export POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-ci-pg-pass}"
export MONGO_PASSWORD="${MONGO_PASSWORD:-ci-mongo-pass}"
export MONGO_USERNAME="${MONGO_USERNAME:-mongo}"
# RabbitMQ: use the docker-compose default user "guest" for integration tests.
# Using a custom user triggers a 300s retry storm in the gateway producer when
# the custom user isn't yet initialized — the "guest" user is pre-configured
# and available immediately without any race condition.
export RABBITMQ_PASSWORD="guest"
export RABBITMQ_USERNAME="guest"
export RABBITMQ_DEFAULT_USER="guest"
export RABBITMQ_DEFAULT_PASS="guest"
export REDIS_PASSWORD="${REDIS_PASSWORD:-ci-redis-pass}"
export GRAFANA_ADMIN_PASSWORD="${GRAFANA_ADMIN_PASSWORD:-ci-grafana-pass}"

# shellcheck source=scripts/lib/prepare-compose-env.sh
source "${ROOT_DIR}/scripts/lib/prepare-compose-env.sh"
prepare_compose_env "${ROOT_DIR}"

# env-aliases.sh may export a stale or k8s-targeted MONGO_URI; override here
# with the compose-internal service hostname before docker compose reads it.
export MONGO_URI="mongodb://${MONGO_USERNAME:-mongo}:${MONGO_PASSWORD:-mongo}@mongodb:${MONGO_PORT:-27017}/${MONGO_DATABASE:-video_converter}?authSource=${MONGO_AUTH_SOURCE:-admin}"

cleanup() {
  if [ "${NO_CLEANUP:-}" = "1" ]; then
    return
  fi
  docker compose --env-file "${COMPOSE_ENV_FILE}" down --remove-orphans 2>/dev/null || true
}
trap cleanup EXIT

# Spin up only the long-running services needed for API-level integration tests.
# frontend is excluded — not exercised by the test suite.
# minio-init is excluded from --wait: it is a one-shot init container that exits
# with code 0 after creating buckets, and docker compose --wait treats any exited
# container (even exit-0) as a startup failure.  It is started separately below.
# `--wait` honors healthchecks and depends_on:service_healthy chains, making
# startup deterministic — fails fast rather than racing on fixed sleeps.
LONG_RUNNING_SERVICES=(postgres mongodb redis rabbitmq minio auth gateway converter notification)
if ! docker compose --env-file "${COMPOSE_ENV_FILE}" up -d --build --wait --wait-timeout 360 \
    "${LONG_RUNNING_SERVICES[@]}"; then
  echo "=== Stack did not become healthy; status + logs follow ==="
  docker compose --env-file "${COMPOSE_ENV_FILE}" ps || true
  docker compose --env-file "${COMPOSE_ENV_FILE}" logs --tail=80 \
    auth gateway converter notification 2>&1 || true
  exit 1
fi

# Run the minio-init one-shot container to create S3 buckets (minio is now healthy).
# docker compose up -d starts it; docker wait blocks until it exits; exit code is checked.
docker compose --env-file "${COMPOSE_ENV_FILE}" up -d minio-init
MINIO_INIT_CONTAINER="${MINIO_INIT_CONTAINER_NAME:-minio-init}"
minio_rc=$(docker wait "${MINIO_INIT_CONTAINER}" 2>/dev/null || echo "1")
if [ "${minio_rc}" != "0" ]; then
  echo "=== minio-init failed (exit ${minio_rc}) ==="
  docker logs "${MINIO_INIT_CONTAINER}" 2>&1 || true
  exit 1
fi

# Belt-and-suspenders: confirm RabbitMQ AMQP is actually accepting connections
# (its health check can pass slightly before the AMQP listener is ready).
for _ in $(seq 1 40); do
  if docker exec rabbitmq rabbitmq-diagnostics check_running >/dev/null 2>&1; then
    break
  fi
  sleep 3
done

GATEWAY_URL="${GATEWAY_BASE_URL:-http://localhost:8080}"
echo "Waiting for gateway to accept HTTP requests..."
for _ in $(seq 1 36); do
  if curl -sf "${GATEWAY_URL}/health" >/dev/null 2>&1; then
    echo "Gateway is ready."
    break
  fi
  sleep 5
done

export INTEGRATION_TESTS=true
export PRODUCTION_VALIDATION=true
export GATEWAY_BASE_URL="${GATEWAY_BASE_URL:-http://localhost:8080}"
export AUTH_BASE_URL="${AUTH_BASE_URL:-http://localhost:8000}"
export CONVERTER_BASE_URL="${CONVERTER_BASE_URL:-http://localhost:8002}"
export NOTIFICATION_BASE_URL="${NOTIFICATION_BASE_URL:-http://localhost:8003}"
export S3_UPLOAD_BUCKET="${S3_UPLOAD_BUCKET:-video-uploads}"
export S3_AUDIO_BUCKET="${S3_AUDIO_BUCKET:-audio-outputs}"
export AWS_S3_VIDEO_BUCKET="${AWS_S3_VIDEO_BUCKET:-${S3_UPLOAD_BUCKET}}"
export AWS_S3_AUDIO_BUCKET="${AWS_S3_AUDIO_BUCKET:-${S3_AUDIO_BUCKET}}"
export AWS_S3_ENDPOINT_URL="${AWS_S3_ENDPOINT_URL:-http://127.0.0.1:9000}"
export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-minioadmin}"
export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-minioadmin}"
export AWS_REGION="${AWS_REGION:-eu-central-1}"

if [ ! -d "${ROOT_DIR}/.venv" ]; then
  python3 -m venv "${ROOT_DIR}/.venv"
fi
# shellcheck disable=SC1091
source "${ROOT_DIR}/.venv/bin/activate"
pip install -q pytest httpx requests boto3
for service in gateway auth converter notification; do
  pip install -q -r "${ROOT_DIR}/services/${service}/requirements.txt"
done

echo "=== Running integration and e2e tests ==="
python -m pytest tests/integration tests/e2e -v --tb=short

echo "=== RabbitMQ queue health check ==="
chmod +x scripts/check-rabbitmq-video-queues.sh
COMPOSE_ENV_FILE="${COMPOSE_ENV_FILE}" bash scripts/check-rabbitmq-video-queues.sh compose

echo "=== Integration tests passed ==="
