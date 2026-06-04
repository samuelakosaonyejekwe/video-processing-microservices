#!/bin/bash
# backup-prometheus.sh — Archive the Prometheus TSDB (/prometheus) to S3 so metrics
# HISTORY survives a full-mode destroy. Prometheus storage is an emptyDir (already
# lost on any pod restart), so this is best-effort: a running-tar copy (Prometheus'
# WAL makes it crash-consistent enough). Does NOT change the live deployment.
# Restore: restore-prometheus.sh.
#
# Env: DATABASE_BACKUP_BUCKET, kubectl context, AWS creds. K8S_NAMESPACE default
# video-processing. SKIP_PROMETHEUS_BACKUP=true to skip.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/env-aliases.sh
source "${ROOT_DIR}/scripts/lib/env-aliases.sh"
log() { echo "[$(date -u '+%H:%M:%S')] backup-prometheus: $*"; }

[ "${SKIP_PROMETHEUS_BACKUP:-false}" = "true" ] && { log "skipped"; exit 0; }
: "${DATABASE_BACKUP_BUCKET:?Missing DATABASE_BACKUP_BUCKET}"
BUCKET="${DATABASE_BACKUP_BUCKET}"; NS="${K8S_NAMESPACE:-video-processing}"
TS="$(date -u +%Y%m%d-%H%M%S)"

POD="$(kubectl -n "${NS}" get pods -l app=prometheus -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)"
[ -n "${POD}" ] || { echo "ERROR: no prometheus pod in ns ${NS}" >&2; exit 1; }

log "archiving /prometheus from ${POD} (best-effort, non-disruptive)..."
if kubectl -n "${NS}" exec "${POD}" -- tar czf - -C /prometheus . 2>/dev/null \
     | aws s3 cp --sse AES256 - "s3://${BUCKET}/prometheus/data-${TS}.tgz"; then
  aws s3 cp --sse AES256 "s3://${BUCKET}/prometheus/data-${TS}.tgz" "s3://${BUCKET}/prometheus/data-latest.tgz"
  log "backed up -> s3://${BUCKET}/prometheus/data-{${TS},latest}.tgz"
else
  echo "WARNING: prometheus archive failed (metrics history is non-critical observability data)." >&2
fi
