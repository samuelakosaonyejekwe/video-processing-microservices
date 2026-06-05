#!/bin/bash
# restore-grafana.sh — Re-import hand-built Grafana dashboards from S3 (counterpart
# to backup-grafana.sh). Provisioned dashboards come back from ConfigMaps already.
#
# Env: DATABASE_BACKUP_BUCKET, kubectl context, AWS creds. K8S_NAMESPACE default
# video-processing. RESTORE_GRAFANA=false to skip.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/env-aliases.sh
source "${ROOT_DIR}/scripts/lib/env-aliases.sh"
log() { echo "[$(date -u '+%H:%M:%S')] restore-grafana: $*"; }
warn() { echo "[$(date -u '+%H:%M:%S')] restore-grafana: WARNING: $*" >&2; }

[ "${RESTORE_GRAFANA:-true}" != "true" ] && { log "skipped"; exit 0; }
: "${DATABASE_BACKUP_BUCKET:?Missing DATABASE_BACKUP_BUCKET}"
BUCKET="${DATABASE_BACKUP_BUCKET}"; NS="${K8S_NAMESPACE:-video-processing}"; PORT=3011

if ! aws s3 ls "s3://${BUCKET}/grafana/dashboards-latest.tgz" >/dev/null 2>&1; then
  log "no dashboard backup found — nothing to restore (provisioned dashboards load from ConfigMap)"; exit 0
fi

USER="$(kubectl -n "${NS}" get secret grafana-secret -o jsonpath='{.data.GRAFANA_ADMIN_USER}' | base64 -d)"
PASS="$(kubectl -n "${NS}" get secret grafana-secret -o jsonpath='{.data.GRAFANA_ADMIN_PASSWORD}' | base64 -d)"
kubectl -n "${NS}" rollout status deploy/grafana --timeout=180s >/dev/null 2>&1 || true
kubectl -n "${NS}" port-forward svc/grafana-service ${PORT}:3000 >/dev/null 2>&1 &
PF=$!; trap 'kill $PF 2>/dev/null' EXIT; sleep 4
BASE="http://localhost:${PORT}"

tmp="$(mktemp -d)"
aws s3 cp "s3://${BUCKET}/grafana/dashboards-latest.tgz" - | tar xzf - -C "${tmp}"
n=0
for f in "${tmp}"/*.json; do
  [ -e "$f" ] || continue
  body="$(python3 -c "import json,sys;d=json.load(open('$f'));dash=d['dashboard'];dash.pop('id',None);print(json.dumps({'dashboard':dash,'overwrite':True}))" 2>/dev/null)" || { warn "skip malformed $f"; continue; }
  code="$(curl -s -o /dev/null -w '%{http_code}' -u "${USER}:${PASS}" -X POST "${BASE}/api/dashboards/db" -H 'Content-Type: application/json' -d "${body}")"
  [ "$code" = "200" ] && n=$((n+1)) || warn "import failed (HTTP $code) for $(basename "$f")"
done
rm -rf "${tmp}"
log "restored ${n} hand-built dashboard(s)"
