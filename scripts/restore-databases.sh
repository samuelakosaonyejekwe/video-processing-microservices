#!/bin/bash
# restore-databases.sh — Restore Postgres + MongoDB from the latest S3 dumps.
#
# Streams the latest dumps from S3 into the DB pods via `kubectl exec`, dropping
# existing objects first (pg_dump was taken with --clean --if-exists; mongorestore
# uses --drop) so the result matches the dumped state exactly. Idempotent and safe
# to run after the StatefulSets are up and migrations have created the schema.
#
# Used by start-platform after a full recreate to restore the pre-shutdown data.
#
# Required: DATABASE_BACKUP_BUCKET, a working kubectl context, AWS credentials.
# Set RESTORE_DATABASES=false to skip (e.g. a deliberate fresh start).
set -euo pipefail

if [ "${RESTORE_DATABASES:-true}" != "true" ]; then
  echo "RESTORE_DATABASES != true; skipping database restore."
  exit 0
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/env-aliases.sh
source "${ROOT_DIR}/scripts/lib/env-aliases.sh"

DB_NS="${DATABASE_NAMESPACE:-database}"
APP_NS="${K8S_NAMESPACE:-video-processing}"
: "${DATABASE_BACKUP_BUCKET:?Missing DATABASE_BACKUP_BUCKET}"
BUCKET="${DATABASE_BACKUP_BUCKET}"

PG_POD="${POSTGRES_RELEASE_NAME:-postgresql}-0"
MONGO_POD="${MONGODB_RELEASE_NAME:-mongodb}-0"

log()  { echo "[$(date -u '+%H:%M:%S')] $*"; }
warn() { echo "[$(date -u '+%H:%M:%S')] WARNING: $*" >&2; }

PG_USER="$(kubectl -n "${DB_NS}" get secret postgres-secret -o jsonpath='{.data.POSTGRES_USER}' | base64 -d)"
PG_PW="$(kubectl -n "${DB_NS}" get secret postgres-secret -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 -d)"
PG_DB="$(kubectl -n "${APP_NS}" get configmap auth-config -o jsonpath='{.data.POSTGRES_DB}' 2>/dev/null || true)"
PG_DB="${PG_DB:-${POSTGRES_DB:-video_to_audio_converter}}"

MONGO_USER="$(kubectl -n "${APP_NS}" get secret mongodb-secret -o jsonpath='{.data.MONGO_USERNAME}' | base64 -d 2>/dev/null || echo mongo)"
MONGO_PW="$(kubectl -n "${APP_NS}" get secret mongodb-secret -o jsonpath='{.data.MONGO_PASSWORD}' | base64 -d)"
MONGO_DB="$(kubectl -n "${APP_NS}" get secret mongodb-secret -o jsonpath='{.data.MONGO_DATABASE}' | base64 -d 2>/dev/null || echo video_converter)"

# Wait for DB pods to be ready before restoring.
kubectl -n "${DB_NS}" wait --for=condition=ready "pod/${PG_POD}" --timeout=180s >/dev/null 2>&1 || warn "Postgres pod not ready"
kubectl -n "${DB_NS}" wait --for=condition=ready "pod/${MONGO_POD}" --timeout=180s >/dev/null 2>&1 || warn "Mongo pod not ready"

# --- Postgres ---
if aws s3 ls "s3://${BUCKET}/postgres/latest.sql.gz" >/dev/null 2>&1; then
  log "Restoring Postgres db '${PG_DB}' from s3://${BUCKET}/postgres/latest.sql.gz ..."
  aws s3 cp "s3://${BUCKET}/postgres/latest.sql.gz" - \
    | gzip -dc \
    | kubectl -n "${DB_NS}" exec -i "${PG_POD}" -- sh -c \
        "PGPASSWORD='${PG_PW}' psql -v ON_ERROR_STOP=0 -U '${PG_USER}' -d '${PG_DB}'" >/dev/null
  log "Postgres restore complete."
else
  warn "No Postgres dump at s3://${BUCKET}/postgres/latest.sql.gz — skipping (fresh DB)."
fi

# --- MongoDB ---
if aws s3 ls "s3://${BUCKET}/mongodb/latest.archive.gz" >/dev/null 2>&1; then
  log "Restoring Mongo db '${MONGO_DB}' from s3://${BUCKET}/mongodb/latest.archive.gz ..."
  aws s3 cp "s3://${BUCKET}/mongodb/latest.archive.gz" - \
    | kubectl -n "${DB_NS}" exec -i "${MONGO_POD}" -- sh -c \
        "mongorestore --uri='mongodb://${MONGO_USER}:${MONGO_PW}@127.0.0.1:27017/?authSource=admin' --archive --gzip --drop --nsInclude='${MONGO_DB}.*'" >/dev/null
  log "Mongo restore complete."
else
  warn "No Mongo dump at s3://${BUCKET}/mongodb/latest.archive.gz — skipping (fresh DB)."
fi

log "Database restore complete."
