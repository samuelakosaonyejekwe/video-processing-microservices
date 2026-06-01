#!/bin/bash
# Resolve compose runtime env and PEM secrets for local docker compose runs.

prepare_compose_env() {
  local root_dir="$1"
  local runtime_env="${root_dir}/.env.compose.runtime"
  local secrets_dir="${root_dir}/.compose-secrets"

  : > "${runtime_env}"

  if [ -f "${root_dir}/.env" ]; then
    set +u
    set -a
    # shellcheck disable=SC1091
    source "${root_dir}/.env"
    set +a
    set -u
  fi

  # Unset MONGO_URI before sourcing env-aliases.sh so that the broken template
  # value built by sourcing .env (where ${MONGO_USERNAME} etc. are all empty)
  # does not freeze in place and block env-aliases.sh from rebuilding it.
  unset MONGO_URI

  # shellcheck source=scripts/lib/env-aliases.sh
  source "${root_dir}/scripts/lib/env-aliases.sh"

  # Force compose-internal hostname regardless of what env-aliases.sh built.
  # env-aliases.sh uses the k8s service name; compose uses the service label.
  export MONGO_URI="mongodb://${MONGO_USERNAME:-mongo}:${MONGO_PASSWORD:-mongo}@mongodb:${MONGO_PORT:-27017}/${MONGO_DATABASE:-video_converter}?authSource=${MONGO_AUTH_SOURCE:-admin}"

  write_env() {
    local key="$1"
    local value="${!key:-}"
    if [ -n "$value" ]; then
      printf '%s=%q\n' "$key" "$value" >> "${runtime_env}"
    fi
  }

  for key in \
    APP_ENV POSTGRES_HOST POSTGRES_PORT POSTGRES_USER POSTGRES_PASSWORD POSTGRES_DB POSTGRES_SSL_MODE \
    RABBITMQ_PORT RABBITMQ_USERNAME RABBITMQ_PASSWORD RABBITMQ_DEFAULT_USER RABBITMQ_DEFAULT_PASS \
    RABBITMQ_EXCHANGE \
    JWT_ACTIVE_KID \
    GATEWAY_APP_PORT AUTH_APP_PORT CONVERTER_APP_PORT NOTIFICATION_APP_PORT \
    VIDEO_UPLOAD_QUEUE NOTIFICATION_QUEUE GATEWAY_EVENTS_QUEUE \
    MONGO_USERNAME MONGO_PASSWORD MONGO_DATABASE MONGO_PORT MONGO_URI \
    AWS_REGION AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY \
    S3_UPLOAD_BUCKET S3_AUDIO_BUCKET SMTP_HOST SMTP_PORT SMTP_EMAIL SMTP_PASSWORD SMTP_FROM_EMAIL \
    CORS_ALLOWED_ORIGINS; do
    write_env "$key"
  done

  if [ -f "${root_dir}/jwt-private.pem" ]; then
    echo "JWT_ALGORITHM=RS256" >> "${runtime_env}"
  else
    write_env "JWT_ALGORITHM"
    write_env "JWT_SECRET"
  fi

  export JWT_ISSUER="${JWT_ISSUER:-${JWT_TOKEN_ISSUER:-video-converter-platform}}"
  export JWT_AUDIENCE="${JWT_AUDIENCE:-${JWT_TOKEN_AUDIENCE:-video-converter-users}}"
  export JWT_ALGORITHM="${JWT_ALGORITHM:-RS256}"
  printf 'JWT_ISSUER=%q\n' "${JWT_ISSUER}" >> "${runtime_env}"
  printf 'JWT_AUDIENCE=%q\n' "${JWT_AUDIENCE}" >> "${runtime_env}"

  if [ -f "${root_dir}/jwt-private.pem" ] && [ ! -f "${root_dir}/jwt-public.pem" ]; then
    openssl rsa -in "${root_dir}/jwt-private.pem" -pubout -out "${root_dir}/jwt-public.pem" 2>/dev/null || true
  fi

  mkdir -p "${secrets_dir}"
  if [ -f "${root_dir}/jwt-private.pem" ]; then
    cp "${root_dir}/jwt-private.pem" "${secrets_dir}/"
    cp "${root_dir}/jwt-public.pem" "${secrets_dir}/"
    chmod 644 "${secrets_dir}/jwt-private.pem" "${secrets_dir}/jwt-public.pem"
  fi

  export COMPOSE_ENV_FILE="${runtime_env}"
  export COMPOSE_SECRETS_DIR="${secrets_dir}"
}
