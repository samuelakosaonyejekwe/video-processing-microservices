#!/usr/bin/env bash

set -euo pipefail

PGPASSWORD="${POSTGRES_PASSWORD}" psql \
  -h "${POSTGRES_HOST}" \
  -p "${POSTGRES_PORT}" \
  -U "${POSTGRES_USER}" \
  -d "${POSTGRES_DB}" \
  -f databases/postgresql/schema.sql

shopt -s nullglob
for migration in databases/postgresql/migrations/*.sql; do

  echo "Running migration: ${migration}"

  PGPASSWORD="${POSTGRES_PASSWORD}" psql \
    -h "${POSTGRES_HOST}" \
    -p "${POSTGRES_PORT}" \
    -U "${POSTGRES_USER}" \
    -d "${POSTGRES_DB}" \
    -f "${migration}"

done