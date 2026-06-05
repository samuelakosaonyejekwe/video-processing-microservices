#!/bin/bash
# backup-redis.sh — Snapshot Redis (RDB) to S3 so its data survives a full-mode
# destroy (the redis PVC is deleted). Redis is primarily a cache, but this makes
# the restart truly zero-loss. Restore: restore-redis.sh.
#
# Env: DATABASE_BACKUP_BUCKET, kubectl context, AWS creds. K8S_NAMESPACE default
# video-processing. SKIP_REDIS_BACKUP=true to skip.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/env-aliases.sh
source "${ROOT_DIR}/scripts/lib/env-aliases.sh"
log() { echo "[$(date -u '+%H:%M:%S')] backup-redis: $*"; }

[ "${SKIP_REDIS_BACKUP:-false}" = "true" ] && { log "skipped"; exit 0; }
: "${DATABASE_BACKUP_BUCKET:?Missing DATABASE_BACKUP_BUCKET}"
BUCKET="${DATABASE_BACKUP_BUCKET}"; NS="${K8S_NAMESPACE:-video-processing}"
TS="$(date -u +%Y%m%d-%H%M%S)"

POD="$(kubectl -n "${NS}" get pods -l app=redis -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)"
[ -n "${POD}" ] || { echo "ERROR: no redis pod in ns ${NS}" >&2; exit 1; }
PW="$(kubectl -n "${NS}" get secret redis-secret -o jsonpath='{.data.REDIS_PASSWORD}' | base64 -d 2>/dev/null || true)"
AUTH=""; [ -n "${PW}" ] && AUTH="-a ${PW} --no-auth-warning"

log "redis ${NS}/${POD}: synchronous SAVE..."
kubectl -n "${NS}" exec "${POD}" -- sh -c "redis-cli ${AUTH} SAVE" >/dev/null
log "streaming dump.rdb to S3..."
kubectl -n "${NS}" exec "${POD}" -- cat /data/dump.rdb \
  | aws s3 cp --sse AES256 - "s3://${BUCKET}/redis/dump-${TS}.rdb"
aws s3 cp --sse AES256 "s3://${BUCKET}/redis/dump-${TS}.rdb" "s3://${BUCKET}/redis/dump-latest.rdb"
log "backed up -> s3://${BUCKET}/redis/dump-{${TS},latest}.rdb"
