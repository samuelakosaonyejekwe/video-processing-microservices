#!/usr/bin/env bash

set -euo pipefail

TIMESTAMP=$(date +%Y%m%d-%H%M%S)

BACKUP_DIR="mongodb-backup-${TIMESTAMP}"

mongodump \
  --uri="${MONGO_URI}" \
  --out="${BACKUP_DIR}"

aws s3 cp \
  "${BACKUP_DIR}" \
  "s3://${DATABASE_BACKUP_BUCKET}/mongodb/${BACKUP_DIR}" \
  --recursive