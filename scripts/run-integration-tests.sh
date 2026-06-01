#!/bin/bash
# Start the local stack and run integration/e2e tests against it.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

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

# First pass: build images and start all containers.
docker compose --env-file "${COMPOSE_ENV_FILE}" up -d --build || true

# RabbitMQ may take >30s to boot from a fresh volume, which can fail dependent
# services on the first pass (health-check race). A second `up -d` starts any
# containers that were skipped due to that transient dependency failure.
sleep 10
docker compose --env-file "${COMPOSE_ENV_FILE}" up -d || true

echo "=== Waiting for services ==="
for _ in $(seq 1 60); do
  if curl -sf http://localhost:8080/health >/dev/null 2>&1 \
    && curl -sf http://localhost:8000/health >/dev/null 2>&1 \
    && curl -sf http://localhost:8002/health >/dev/null 2>&1 \
    && curl -sf http://localhost:8003/health >/dev/null 2>&1 \
    && curl -sf http://localhost:9000/minio/health/live >/dev/null 2>&1; then
    break
  fi
  sleep 3
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
export AWS_REGION="${AWS_REGION:-us-east-1}"

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
