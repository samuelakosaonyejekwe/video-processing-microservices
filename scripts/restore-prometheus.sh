#!/bin/bash
# restore-prometheus.sh — Restore the Prometheus TSDB from S3 (counterpart to
# backup-prometheus.sh) so metrics history carries across a full recreate. Streams
# the archive into the fresh pod's /prometheus and restarts Prometheus to load it.
#
# Env: DATABASE_BACKUP_BUCKET, kubectl context, AWS creds. K8S_NAMESPACE default
# video-processing. RESTORE_PROMETHEUS=false to skip.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/env-aliases.sh
source "${ROOT_DIR}/scripts/lib/env-aliases.sh"
log() { echo "[$(date -u '+%H:%M:%S')] restore-prometheus: $*"; }
warn() { echo "[$(date -u '+%H:%M:%S')] restore-prometheus: WARNING: $*" >&2; }

[ "${RESTORE_PROMETHEUS:-true}" != "true" ] && { log "skipped"; exit 0; }
: "${DATABASE_BACKUP_BUCKET:?Missing DATABASE_BACKUP_BUCKET}"
BUCKET="${DATABASE_BACKUP_BUCKET}"; NS="${K8S_NAMESPACE:-video-processing}"

aws s3 ls "s3://${BUCKET}/prometheus/data-latest.tgz" >/dev/null 2>&1 || { log "no prometheus backup — skipping (metrics will start fresh)"; exit 0; }
POD="$(kubectl -n "${NS}" get pods -l app=prometheus -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)"
[ -n "${POD}" ] || { warn "no prometheus pod"; exit 0; }
kubectl -n "${NS}" wait --for=condition=ready "pod/${POD}" --timeout=180s >/dev/null 2>&1 || true

log "streaming TSDB archive into ${POD}:/prometheus ..."
if aws s3 cp "s3://${BUCKET}/prometheus/data-latest.tgz" - \
     | kubectl -n "${NS}" exec -i "${POD}" -- tar xzf - -C /prometheus 2>/dev/null; then
  kubectl -n "${NS}" rollout restart deploy/prometheus >/dev/null 2>&1 || true
  kubectl -n "${NS}" rollout status deploy/prometheus --timeout=180s >/dev/null 2>&1 || true
  log "prometheus history restored."
else
  warn "prometheus restore failed — metrics start fresh (non-critical)."
fi
