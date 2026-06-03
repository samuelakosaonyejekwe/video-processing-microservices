#!/bin/bash
# Resolve compose runtime env and PEM secrets for local docker compose runs.

prepare_compose_env() {
  local root_dir="$1"
  local runtime_env="${root_dir}/.env.compose.runtime"
  local secrets_dir="${root_dir}/.compose-secrets"

  # This runtime env file holds AWS keys and all DB/RabbitMQ/SMTP passwords.
  # Create it world-unreadable (0600) and keep it that way across later appends.
  ( umask 077; : > "${runtime_env}" )
  chmod 600 "${runtime_env}" 2>/dev/null || true

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

  # Local docker compose is a development environment. The repo .env carries
  # production/k8s values (incl. APP_ENV=production), which makes services enforce
  # production-only required secrets (e.g. notification's SMTP_PASSWORD) that the
  # local stack does not provide, so they crash on boot. Pin development mode
  # (overridable via COMPOSE_APP_ENV) to match the compose service defaults.
  export APP_ENV="${COMPOSE_APP_ENV:-development}"

  # Force compose-internal hostnames regardless of what .env / env-aliases.sh
  # built — those carry Kubernetes service DNS names (e.g.
  # postgresql.database.svc.cluster.local) which are unreachable from compose.
  # Compose addresses services by their compose name.
  export POSTGRES_HOST="postgres"
  export MONGO_HOST="mongodb"
  export REDIS_HOST="redis"
  export RABBITMQ_HOST="rabbitmq"
  export MONGO_URI="mongodb://${MONGO_USERNAME:-mongo}:${MONGO_PASSWORD:-mongo}@mongodb:${MONGO_PORT:-27017}/${MONGO_DATABASE:-video_converter}?authSource=${MONGO_AUTH_SOURCE:-admin}"

  write_env() {
    local key="$1"
    local value="${!key:-}"
    if [ -n "$value" ]; then
      # Plain KEY=value: a docker compose env_file is read literally (NOT shell
      # parsed), so %q-style quoting would inject stray backslashes (e.g. the
      # "?" in a Mongo URI would become "\?") and corrupt the value.
      printf '%s=%s\n' "$key" "$value" >> "${runtime_env}"
    fi
  }

  for key in \
    APP_ENV POSTGRES_HOST POSTGRES_PORT POSTGRES_USER POSTGRES_PASSWORD POSTGRES_DB POSTGRES_SSL_MODE \
    RABBITMQ_HOST RABBITMQ_PORT RABBITMQ_USERNAME RABBITMQ_PASSWORD RABBITMQ_DEFAULT_USER RABBITMQ_DEFAULT_PASS \
    RABBITMQ_EXCHANGE \
    REDIS_HOST REDIS_PORT REDIS_PASSWORD \
    JWT_ACTIVE_KID \
    GATEWAY_APP_PORT AUTH_APP_PORT CONVERTER_APP_PORT NOTIFICATION_APP_PORT \
    VIDEO_UPLOAD_QUEUE NOTIFICATION_QUEUE GATEWAY_EVENTS_QUEUE \
    MONGO_HOST MONGO_USERNAME MONGO_PASSWORD MONGO_DATABASE MONGO_PORT MONGO_URI \
    AWS_REGION AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY \
    S3_UPLOAD_BUCKET S3_AUDIO_BUCKET SMTP_HOST SMTP_PORT SMTP_EMAIL SMTP_PASSWORD SMTP_FROM_EMAIL \
    CORS_ALLOWED_ORIGINS; do
    write_env "$key"
  done

  export JWT_ISSUER="${JWT_ISSUER:-${JWT_TOKEN_ISSUER:-video-converter-platform}}"
  export JWT_AUDIENCE="${JWT_AUDIENCE:-${JWT_TOKEN_AUDIENCE:-video-converter-users}}"
  export JWT_ALGORITHM="${JWT_ALGORITHM:-RS256}"
  printf 'JWT_ISSUER=%s\n' "${JWT_ISSUER}" >> "${runtime_env}"
  printf 'JWT_AUDIENCE=%s\n' "${JWT_AUDIENCE}" >> "${runtime_env}"

  # Ensure RSA keypair exists in secrets_dir so docker compose bind-mounts
  # get a real file at /run/secrets/*.pem, not an empty directory (which is
  # what Docker creates when the host source path does not exist).
  # Priority: user-supplied keys at root_dir → already-generated keys in
  # secrets_dir (preserve across re-runs) → generate a throwaway pair.
  mkdir -p "${secrets_dir}"
  chmod 700 "${secrets_dir}" 2>/dev/null || true
  if [ -f "${root_dir}/jwt-private.pem" ]; then
    cp "${root_dir}/jwt-private.pem" "${secrets_dir}/jwt-private.pem"
    if [ -f "${root_dir}/jwt-public.pem" ]; then
      cp "${root_dir}/jwt-public.pem" "${secrets_dir}/jwt-public.pem"
    else
      openssl rsa -in "${secrets_dir}/jwt-private.pem" -pubout \
        -out "${secrets_dir}/jwt-public.pem" 2>/dev/null || true
    fi
  elif [ ! -f "${secrets_dir}/jwt-private.pem" ]; then
    openssl genrsa -out "${secrets_dir}/jwt-private.pem" 2048 2>/dev/null
    openssl rsa -in "${secrets_dir}/jwt-private.pem" -pubout \
      -out "${secrets_dir}/jwt-public.pem" 2>/dev/null || true
  fi
  # Host-side protection comes from the 0700 secrets_dir above (other users
  # can't traverse into it). The key files themselves stay 0644 because compose
  # bind-mounts them read-only into containers that run as a NON-root user with a
  # different UID — 0600 would make the mounted key unreadable and crash the app.
  chmod 644 "${secrets_dir}/jwt-private.pem" 2>/dev/null || true
  chmod 644 "${secrets_dir}/jwt-public.pem" 2>/dev/null || true
  # Always RS256 — RSA material is always present in secrets_dir after the block above.
  echo "JWT_ALGORITHM=RS256" >> "${runtime_env}"

  export COMPOSE_ENV_FILE="${runtime_env}"
  export COMPOSE_SECRETS_DIR="${secrets_dir}"
}
