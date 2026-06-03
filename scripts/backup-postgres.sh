#!/usr/bin/env bash

set -euo pipefail

TIMESTAMP=$(date +%Y%m%d-%H%M%S)

BACKUP_FILE="postgres-backup-${TIMESTAMP}.sql"

BACKUP_DIR="$(mktemp -d)"
chmod 700 "${BACKUP_DIR}"
BACKUP_PATH="${BACKUP_DIR}/${BACKUP_FILE}"

PGPASSWORD="${POSTGRES_PASSWORD}" pg_dump \
  -h "${POSTGRES_HOST}" \
  -p "${POSTGRES_PORT}" \
  -U "${POSTGRES_USER}" \
  -d "${POSTGRES_DB}" \
  > "${BACKUP_PATH}"

aws s3 cp \
  --sse aws:kms \
  "${BACKUP_PATH}" \
  "s3://${DATABASE_BACKUP_BUCKET}/postgres/${BACKUP_FILE}"

rm -rf "${BACKUP_DIR}"