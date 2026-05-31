#!/bin/bash
# Shared secret sanitization for render and runtime credential sync scripts.

strip_control_chars() {
  printf '%s' "${1}" | tr -d '\000-\010\013\014\016-\037'
}

sanitize_secret_env() {
  local key
  for key in \
    JWT_SECRET JWT_PRIVATE_KEY JWT_PUBLIC_KEY JWT_REFRESH_TOKEN_SECRET JWT_SESSION_SECRET \
    POSTGRES_PASSWORD POSTGRES_USER MONGO_PASSWORD MONGO_USERNAME \
    RABBITMQ_PASSWORD RABBITMQ_USERNAME RABBITMQ_URI RABBITMQ_ERLANG_COOKIE \
    RABBITMQ_DEFAULT_USER RABBITMQ_DEFAULT_PASS \
    SMTP_USERNAME SMTP_PASSWORD SMTP_EMAIL REDIS_PASSWORD; do
    if [ -n "${!key:-}" ]; then
      export "${key}=$(strip_control_chars "${!key}")"
    fi
  done
}
