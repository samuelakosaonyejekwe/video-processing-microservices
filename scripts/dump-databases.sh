#!/bin/bash
# dump-databases.sh — Logical dump of Postgres + MongoDB to S3.
#
# Runs `pg_dump`/`mongodump` INSIDE the DB pods via `kubectl exec` and streams
# the output straight to S3. No extra container images, IRSA roles, or
# NetworkPolicies are needed (the DB images already ship the dump tools, and the
# runner — CI or local — streams the bytes to S3 with its own AWS credentials).
#
# Used by full-mode shutdown so a destroy+recreate loses NO database data:
#   shutdown (full)  -> dump-databases.sh     (capture point-in-time state)
#   start (recreate) -> restore-databases.sh  (restore exact state)
#
# Required: DATABASE_BACKUP_BUCKET, a working kubectl context, AWS credentials.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/env-aliases.sh
source "${ROOT_DIR}/scripts/lib/env-aliases.sh"

DB_NS="${DATABASE_NAMESPACE:-database}"
APP_NS="${K8S_NAMESPACE:-video-processing}"
: "${DATABASE_BACKUP_BUCKET:?Missing DATABASE_BACKUP_BUCKET}"
BUCKET="${DATABASE_BACKUP_BUCKET}"
TS="$(date -u +%Y%m%d-%H%M%S)"

PG_POD="${POSTGRES_RELEASE_NAME:-postgresql}-0"
MONGO_POD="${MONGODB_RELEASE_NAME:-mongodb}-0"

log() { echo "[$(date -u '+%H:%M:%S')] $*"; }

# --- Resolve credentials from the live cluster secrets (robust local + CI) ---
PG_USER="$(kubectl -n "${DB_NS}" get secret postgres-secret -o jsonpath='{.data.POSTGRES_USER}' | base64 -d)"
PG_PW="$(kubectl -n "${DB_NS}" get secret postgres-secret -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 -d)"
PG_DB="$(kubectl -n "${APP_NS}" get configmap auth-config -o jsonpath='{.data.POSTGRES_DB}' 2>/dev/null || true)"
PG_DB="${PG_DB:-${POSTGRES_DB:-video_to_audio_converter}}"

MONGO_USER="$(kubectl -n "${APP_NS}" get secret mongodb-secret -o jsonpath='{.data.MONGO_USERNAME}' | base64 -d 2>/dev/null || echo mongo)"
MONGO_PW="$(kubectl -n "${APP_NS}" get secret mongodb-secret -o jsonpath='{.data.MONGO_PASSWORD}' | base64 -d)"
MONGO_DB="$(kubectl -n "${APP_NS}" get secret mongodb-secret -o jsonpath='{.data.MONGO_DATABASE}' | base64 -d 2>/dev/null || echo video_converter)"

# --- Postgres ---
log "Dumping Postgres db '${PG_DB}' from ${DB_NS}/${PG_POD} -> s3://${BUCKET}/postgres/${TS}.sql.gz"
kubectl -n "${DB_NS}" exec -i "${PG_POD}" -- sh -c \
  "PGPASSWORD='${PG_PW}' pg_dump -U '${PG_USER}' -d '${PG_DB}' --clean --if-exists --no-owner --no-privileges | gzip -c" \
  | aws s3 cp --sse AES256 - "s3://${BUCKET}/postgres/${TS}.sql.gz"
aws s3 cp --sse AES256 "s3://${BUCKET}/postgres/${TS}.sql.gz" "s3://${BUCKET}/postgres/latest.sql.gz" >/dev/null
log "Postgres dump done (+latest)."

# --- MongoDB ---
log "Dumping Mongo db '${MONGO_DB}' from ${DB_NS}/${MONGO_POD} -> s3://${BUCKET}/mongodb/${TS}.archive.gz"
kubectl -n "${DB_NS}" exec -i "${MONGO_POD}" -- sh -c \
  "mongodump --uri='mongodb://${MONGO_USER}:${MONGO_PW}@127.0.0.1:27017/${MONGO_DB}?authSource=admin' --archive --gzip" \
  | aws s3 cp --sse AES256 - "s3://${BUCKET}/mongodb/${TS}.archive.gz"
aws s3 cp --sse AES256 "s3://${BUCKET}/mongodb/${TS}.archive.gz" "s3://${BUCKET}/mongodb/latest.archive.gz" >/dev/null
log "Mongo dump done (+latest)."

log "Database dump complete -> s3://${BUCKET}/ (postgres/ + mongodb/, latest.* points at this run)."
