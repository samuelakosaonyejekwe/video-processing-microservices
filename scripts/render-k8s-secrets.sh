#!/bin/bash
# Render Kubernetes Secret manifests via kubectl (handles multiline PEM, special chars, numeric passwords).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="${1:?output directory required}"
SECRETS_DIR="${OUTPUT_DIR}/infrastructure/kubernetes/secrets"

# shellcheck source=scripts/lib/env-aliases.sh
source "${ROOT_DIR}/scripts/lib/env-aliases.sh"
# shellcheck source=scripts/lib/secret-sanitize.sh
source "${ROOT_DIR}/scripts/lib/secret-sanitize.sh"

_create_secret() {
  local name="$1"
  local dest="$2"
  shift 2

  local args=()
  while [ "$#" -gt 0 ]; do
    local literal_key="$1"
    local env_var="$2"
    shift 2
    local value="${!env_var:-}"
    if [ -n "$value" ]; then
      args+=(--from-literal="${literal_key}=${value}")
    fi
  done

  if [ "${#args[@]}" -eq 0 ]; then
    echo "ERROR: No values provided for secret ${name}"
    exit 1
  fi

  kubectl create secret generic "${name}" \
    --namespace="${K8S_NAMESPACE}" \
    "${args[@]}" \
    --dry-run=client -o yaml > "${dest}"
}

sanitize_secret_env
finalize_jwt_keys

_validate_jwt_keypair() {
  if [ -z "${JWT_PRIVATE_KEY:-}" ] || [ -z "${JWT_PUBLIC_KEY:-}" ]; then
    echo "ERROR: JWT_PRIVATE_KEY and JWT_PUBLIC_KEY are required for deploy."
    exit 1
  fi

  if ! printf '%s' "${JWT_PRIVATE_KEY}" | openssl pkey -check -noout >/dev/null 2>&1 \
    && ! printf '%s' "${JWT_PRIVATE_KEY}" | openssl rsa -check -noout >/dev/null 2>&1; then
    echo "ERROR: JWT_PRIVATE_KEY is not a valid RSA private key PEM."
    exit 1
  fi

  if ! JWT_PUBLIC_KEY="$(_derive_jwt_public_key "${JWT_PRIVATE_KEY}")"; then
    echo "ERROR: Failed to derive JWT public key from JWT_PRIVATE_KEY."
    exit 1
  fi
  export JWT_PUBLIC_KEY
}

_encode_jwt_secrets_for_k8s() {
  if [ -n "${JWT_PRIVATE_KEY:-}" ]; then
    JWT_PRIVATE_KEY="$(
      printf '%s' "${JWT_PRIVATE_KEY}" | base64 -w0 2>/dev/null || printf '%s' "${JWT_PRIVATE_KEY}" | base64
    )"
    export JWT_PRIVATE_KEY
  fi
  if [ -n "${JWT_PUBLIC_KEY:-}" ]; then
    JWT_PUBLIC_KEY="$(
      printf '%s' "${JWT_PUBLIC_KEY}" | base64 -w0 2>/dev/null || printf '%s' "${JWT_PUBLIC_KEY}" | base64
    )"
    export JWT_PUBLIC_KEY
  fi
}

_validate_jwt_keypair
_encode_jwt_secrets_for_k8s

_rabbitmq_component_urlencoded() {
  python3 -c "import urllib.parse, os, sys; print(urllib.parse.quote_plus(os.environ[sys.argv[1]]))" "$1"
}

if [ -n "${RABBITMQ_USERNAME:-}" ] && [ -n "${RABBITMQ_PASSWORD:-}" ] && [ -n "${RABBITMQ_HOST:-}" ]; then
  _rabbitmq_user_encoded="$(_rabbitmq_component_urlencoded RABBITMQ_USERNAME)"
  _rabbitmq_pass_encoded="$(_rabbitmq_component_urlencoded RABBITMQ_PASSWORD)"
  _rabbitmq_vhost="${RABBITMQ_VHOST:-/}"
  if [ "${_rabbitmq_vhost}" = "/" ]; then
    _rabbitmq_vhost_path=""
  else
    _rabbitmq_vhost_path="${_rabbitmq_vhost#/}"
  fi
  export RABBITMQ_URI="amqp://${_rabbitmq_user_encoded}:${_rabbitmq_pass_encoded}@${RABBITMQ_HOST}:${RABBITMQ_PORT:-5672}/${_rabbitmq_vhost_path}"
  export KEDA_RABBITMQ_HOST="${RABBITMQ_URI}"
fi

export POSTGRES_URI="${POSTGRES_URI:-postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@${POSTGRES_HOST}:${POSTGRES_PORT}/${POSTGRES_DB}?sslmode=${POSTGRES_SSL_MODE}}"

mkdir -p "${SECRETS_DIR}"

_create_secret jwt-secret "${SECRETS_DIR}/jwt-secret.yaml" \
  JWT_SECRET JWT_SECRET \
  JWT_PRIVATE_KEY JWT_PRIVATE_KEY \
  JWT_PUBLIC_KEY JWT_PUBLIC_KEY \
  JWT_ACTIVE_KID JWT_ACTIVE_KID \
  JWT_ISSUER JWT_ISSUER \
  JWT_AUDIENCE JWT_AUDIENCE \
  JWT_ALGORITHM JWT_ALGORITHM \
  JWT_ACCESS_TOKEN_EXPIRES_MINUTES JWT_ACCESS_TOKEN_EXPIRES_MINUTES \
  JWT_REFRESH_TOKEN_EXPIRES_DAYS JWT_REFRESH_TOKEN_EXPIRES_DAYS \
  JWT_REFRESH_TOKEN_SECRET JWT_REFRESH_TOKEN_SECRET \
  JWT_SESSION_SECRET JWT_SESSION_SECRET \
  JWT_EXPIRATION_MINUTES JWT_EXPIRATION_MINUTES

_create_secret auth-secret "${SECRETS_DIR}/auth-secret.yaml" \
  JWT_SECRET JWT_SECRET \
  JWT_PRIVATE_KEY JWT_PRIVATE_KEY \
  JWT_PUBLIC_KEY JWT_PUBLIC_KEY \
  JWT_ACTIVE_KID JWT_ACTIVE_KID \
  JWT_ISSUER JWT_ISSUER \
  JWT_AUDIENCE JWT_AUDIENCE \
  JWT_ALGORITHM JWT_ALGORITHM \
  JWT_ACCESS_TOKEN_EXPIRES_MINUTES JWT_ACCESS_TOKEN_EXPIRES_MINUTES \
  JWT_REFRESH_TOKEN_EXPIRES_DAYS JWT_REFRESH_TOKEN_EXPIRES_DAYS \
  JWT_REFRESH_TOKEN_SECRET JWT_REFRESH_TOKEN_SECRET \
  JWT_SESSION_SECRET JWT_SESSION_SECRET \
  POSTGRES_USER POSTGRES_USER \
  POSTGRES_PASSWORD POSTGRES_PASSWORD \
  POSTGRES_DB POSTGRES_DB \
  POSTGRES_HOST POSTGRES_HOST \
  POSTGRES_PORT POSTGRES_PORT \
  POSTGRES_SSL_MODE POSTGRES_SSL_MODE \
  POSTGRES_URI POSTGRES_URI

_create_secret gateway-secret "${SECRETS_DIR}/gateway-secret.yaml" \
  RABBITMQ_USERNAME RABBITMQ_USERNAME \
  RABBITMQ_PASSWORD RABBITMQ_PASSWORD \
  RABBITMQ_HOST RABBITMQ_HOST \
  RABBITMQ_PORT RABBITMQ_PORT \
  RABBITMQ_EXCHANGE RABBITMQ_EXCHANGE \
  VIDEO_UPLOAD_QUEUE VIDEO_UPLOAD_QUEUE \
  NOTIFICATION_QUEUE NOTIFICATION_QUEUE \
  GATEWAY_EVENTS_QUEUE GATEWAY_EVENTS_QUEUE \
  JWT_SECRET JWT_SECRET

# RabbitMQ clustering security depends on a non-guessable Erlang cookie. Enforce
# it here — the actual point of consumption — rather than when env-aliases is
# merely sourced (which happens in many non-deploy contexts).
if [ "${APP_ENV:-development}" = "production" ] && [ -z "${RABBITMQ_ERLANG_COOKIE:-}" ]; then
  echo "ERROR: RABBITMQ_ERLANG_COOKIE must be set in production (provide it via GitHub Secrets)."
  exit 1
fi

_create_secret rabbitmq-secret "${SECRETS_DIR}/rabbitmq-secret.yaml" \
  RABBITMQ_DEFAULT_USER RABBITMQ_DEFAULT_USER \
  RABBITMQ_DEFAULT_PASS RABBITMQ_DEFAULT_PASS \
  RABBITMQ_USERNAME RABBITMQ_USERNAME \
  RABBITMQ_PASSWORD RABBITMQ_PASSWORD \
  RABBITMQ_HOST RABBITMQ_HOST \
  RABBITMQ_PORT RABBITMQ_PORT \
  RABBITMQ_ERLANG_COOKIE RABBITMQ_ERLANG_COOKIE \
  RABBITMQ_AMQP_URL RABBITMQ_AMQP_URL \
  RABBITMQ_URI RABBITMQ_URI \
  KEDA_RABBITMQ_HOST KEDA_RABBITMQ_HOST

_create_secret mongodb-secret "${SECRETS_DIR}/mongodb-secret.yaml" \
  MONGO_HOST MONGO_HOST \
  MONGO_PORT MONGO_PORT \
  MONGO_DATABASE MONGO_DATABASE \
  MONGO_USERNAME MONGO_USERNAME \
  MONGO_PASSWORD MONGO_PASSWORD \
  MONGO_AUTH_SOURCE MONGO_AUTH_SOURCE \
  MONGO_URI MONGO_URI

_create_secret postgres-secret "${SECRETS_DIR}/postgres-secret.yaml" \
  POSTGRES_HOST POSTGRES_HOST \
  POSTGRES_PORT POSTGRES_PORT \
  POSTGRES_DB POSTGRES_DB \
  POSTGRES_USER POSTGRES_USER \
  POSTGRES_PASSWORD POSTGRES_PASSWORD \
  POSTGRES_SSL_MODE POSTGRES_SSL_MODE \
  POSTGRES_URI POSTGRES_URI \
  POSTGRES_POOL_SIZE POSTGRES_POOL_SIZE \
  POSTGRES_MAX_OVERFLOW POSTGRES_MAX_OVERFLOW \
  POSTGRES_POOL_TIMEOUT POSTGRES_POOL_TIMEOUT \
  POSTGRES_POOL_RECYCLE POSTGRES_POOL_RECYCLE \
  POSTGRES_CONNECT_TIMEOUT POSTGRES_CONNECT_TIMEOUT \
  POSTGRES_READ_HOST POSTGRES_READ_HOST \
  POSTGRES_READ_PORT POSTGRES_READ_PORT \
  POSTGRES_BACKUP_BUCKET POSTGRES_BACKUP_BUCKET \
  POSTGRES_BACKUP_PREFIX POSTGRES_BACKUP_PREFIX

_create_secret notification-secret "${SECRETS_DIR}/notification-secret.yaml" \
  SMTP_USERNAME SMTP_USERNAME \
  SMTP_PASSWORD SMTP_PASSWORD \
  SMTP_EMAIL SMTP_EMAIL \
  JWT_SECRET JWT_SECRET

_create_secret redis-secret "${SECRETS_DIR}/redis-secret.yaml" \
  REDIS_PASSWORD REDIS_PASSWORD

export AUTH_SECRET_CHECKSUM="$(
  sha256sum "${SECRETS_DIR}/auth-secret.yaml" | awk '{print $1}' | cut -c1-16
)"

echo "Rendered Kubernetes secrets to ${SECRETS_DIR}"
