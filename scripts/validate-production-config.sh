#!/usr/bin/env bash
set -euo pipefail

validate_production_config() {
  if [ "${APP_ENV:-development}" != "production" ]; then
    return 0
  fi

  local errors=0

  _reject_default() {
    local name="$1"
    local value="$2"
    shift 2
    for forbidden in "$@"; do
      if [ "${value}" = "${forbidden}" ]; then
        echo "Production config error: ${name} must not use default value '${forbidden}'" >&2
        errors=1
      fi
    done
  }

  _reject_default POSTGRES_PASSWORD "${POSTGRES_PASSWORD:-}" postgres
  _reject_default MONGO_PASSWORD "${MONGO_PASSWORD:-}" mongo
  _reject_default RABBITMQ_PASSWORD "${RABBITMQ_PASSWORD:-}" guest
  _reject_default REDIS_PASSWORD "${REDIS_PASSWORD:-}" redis
  _reject_default GRAFANA_ADMIN_PASSWORD "${GRAFANA_ADMIN_PASSWORD:-}" changeme

  if [ "${CORS_ALLOWED_ORIGINS:-*}" = "*" ]; then
    echo "Production config error: CORS_ALLOWED_ORIGINS must not be '*' in production" >&2
    errors=1
  fi

  if [ "${POSTGRES_SSL_MODE:-disable}" = "disable" ]; then
    echo "Production config error: POSTGRES_SSL_MODE must not be 'disable' in production" >&2
    errors=1
  fi

  if [ -z "${REDIS_HOST:-}" ]; then
    echo "Production config error: REDIS_HOST is required in production" >&2
    errors=1
  fi

  if [ "${errors}" -ne 0 ]; then
    return 1
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  validate_production_config
fi
