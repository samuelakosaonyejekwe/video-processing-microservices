#!/bin/bash
# restore-redis.sh — Restore the Redis RDB snapshot from S3 (counterpart to
# backup-redis.sh). Writes dump.rdb into the fresh pod and restarts redis so it
# loads the data on boot.
#
# Env: DATABASE_BACKUP_BUCKET, kubectl context, AWS creds. K8S_NAMESPACE default
# video-processing. RESTORE_REDIS=false to skip.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/env-aliases.sh
source "${ROOT_DIR}/scripts/lib/env-aliases.sh"
log() { echo "[$(date -u '+%H:%M:%S')] restore-redis: $*"; }
warn() { echo "[$(date -u '+%H:%M:%S')] restore-redis: WARNING: $*" >&2; }

[ "${RESTORE_REDIS:-true}" != "true" ] && { log "skipped"; exit 0; }
: "${DATABASE_BACKUP_BUCKET:?Missing DATABASE_BACKUP_BUCKET}"
BUCKET="${DATABASE_BACKUP_BUCKET}"; NS="${K8S_NAMESPACE:-video-processing}"

aws s3 ls "s3://${BUCKET}/redis/dump-latest.rdb" >/dev/null 2>&1 || { log "no redis backup — skipping (cache will warm naturally)"; exit 0; }
POD="$(kubectl -n "${NS}" get pods -l app=redis -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)"
[ -n "${POD}" ] || { warn "no redis pod"; exit 0; }
kubectl -n "${NS}" wait --for=condition=ready "pod/${POD}" --timeout=120s >/dev/null 2>&1 || true

log "writing dump.rdb into ${POD}..."
aws s3 cp "s3://${BUCKET}/redis/dump-latest.rdb" - \
  | kubectl -n "${NS}" exec -i "${POD}" -- sh -c 'cat > /data/dump.rdb'
log "restarting redis to load the snapshot..."
kubectl -n "${NS}" rollout restart deploy/redis >/dev/null 2>&1 || warn "could not rollout-restart redis (restart it manually to load the dump)"
kubectl -n "${NS}" rollout status deploy/redis --timeout=120s >/dev/null 2>&1 || true
log "redis restore complete."
