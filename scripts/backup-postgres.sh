#!/usr/bin/env bash

set -euo pipefail

TIMESTAMP=$(date +%Y%m%d-%H%M%S)

BACKUP_FILE="postgres-backup-${TIMESTAMP}.sql"

PGPASSWORD="${POSTGRES_PASSWORD}" pg_dump \
  -h "${POSTGRES_HOST}" \
  -p "${POSTGRES_PORT}" \
  -U "${POSTGRES_USER}" \
  -d "${POSTGRES_DB}" \
  > "${BACKUP_FILE}"

aws s3 cp \
  "${BACKUP_FILE}" \
  "s3://${DATABASE_BACKUP_BUCKET}/postgres/${BACKUP_FILE}"

rm -f "${BACKUP_FILE}"