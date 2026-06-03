#!/usr/bin/env bash

set -euo pipefail

TIMESTAMP=$(date +%Y%m%d-%H%M%S)

WORK_DIR="$(mktemp -d)"
chmod 700 "${WORK_DIR}"
BACKUP_NAME="mongodb-backup-${TIMESTAMP}"
BACKUP_DIR="${WORK_DIR}/${BACKUP_NAME}"

mongodump \
  --uri="${MONGO_URI}" \
  --out="${BACKUP_DIR}"

aws s3 cp \
  --sse aws:kms \
  "${BACKUP_DIR}" \
  "s3://${DATABASE_BACKUP_BUCKET}/mongodb/${BACKUP_NAME}" \
  --recursive

rm -rf "${WORK_DIR}"