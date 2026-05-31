#!/bin/sh
set -eu

APP_MODULE="${APP_MODULE:-app.main:app}"
BIND_HOST="${BIND_HOST:-0.0.0.0}"
BIND_PORT="${APP_PORT:-8080}"
TLS_PORT="${INTERNAL_TLS_PORT:-8443}"
WORKERS="${GUNICORN_WORKERS:-2}"
WORKER_CLASS="${GUNICORN_WORKER_CLASS:-uvicorn.workers.UvicornWorker}"

start_plain() {
  exec gunicorn "${APP_MODULE}" \
    -k "${WORKER_CLASS}" \
    --bind "${BIND_HOST}:${BIND_PORT}" \
    --workers "${WORKERS}"
}

if [ "${INTERNAL_SERVICE_TLS_ENABLED:-false}" != "true" ]; then
  start_plain
fi

CERT="${INTERNAL_TLS_CERT_PATH:-/etc/internal-tls/tls.crt}"
KEY="${INTERNAL_TLS_KEY_PATH:-/etc/internal-tls/tls.key}"

if [ ! -f "${CERT}" ] || [ ! -f "${KEY}" ]; then
  start_plain
fi

gunicorn "${APP_MODULE}" \
  -k "${WORKER_CLASS}" \
  --bind "${BIND_HOST}:${BIND_PORT}" \
  --workers "${WORKERS}" &

exec gunicorn "${APP_MODULE}" \
  -k "${WORKER_CLASS}" \
  --bind "${BIND_HOST}:${TLS_PORT}" \
  --workers "${WORKERS}" \
  --certfile="${CERT}" \
  --keyfile="${KEY}"
