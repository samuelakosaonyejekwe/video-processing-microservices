#!/bin/bash
# backup-grafana.sh — Export HAND-BUILT Grafana dashboards to S3 so they survive a
# full-mode destroy (the grafana PVC is deleted). Provisioned dashboards are NOT
# exported — they are recreated from ConfigMaps on start. Restore: restore-grafana.sh.
#
# Env: DATABASE_BACKUP_BUCKET, kubectl context, AWS creds. K8S_NAMESPACE (default
# video-processing). SKIP_GRAFANA_BACKUP=true to skip.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/env-aliases.sh
source "${ROOT_DIR}/scripts/lib/env-aliases.sh"
log() { echo "[$(date -u '+%H:%M:%S')] backup-grafana: $*"; }

[ "${SKIP_GRAFANA_BACKUP:-false}" = "true" ] && { log "skipped"; exit 0; }
: "${DATABASE_BACKUP_BUCKET:?Missing DATABASE_BACKUP_BUCKET}"
BUCKET="${DATABASE_BACKUP_BUCKET}"; NS="${K8S_NAMESPACE:-video-processing}"
TS="$(date -u +%Y%m%d-%H%M%S)"; PORT=3010

USER="$(kubectl -n "${NS}" get secret grafana-secret -o jsonpath='{.data.GRAFANA_ADMIN_USER}' | base64 -d)"
PASS="$(kubectl -n "${NS}" get secret grafana-secret -o jsonpath='{.data.GRAFANA_ADMIN_PASSWORD}' | base64 -d)"

kubectl -n "${NS}" port-forward svc/grafana-service ${PORT}:3000 >/dev/null 2>&1 &
PF=$!; trap 'kill $PF 2>/dev/null' EXIT; sleep 4
BASE="http://localhost:${PORT}"
tmp="$(mktemp -d)"

# Save only NON-provisioned (hand-built) dashboards
count=0
for uid in $(curl -s -u "${USER}:${PASS}" "${BASE}/api/search?type=dash-db" | python3 -c "import sys,json;[print(d['uid']) for d in json.load(sys.stdin)]"); do
  d="$(curl -s -u "${USER}:${PASS}" "${BASE}/api/dashboards/uid/${uid}")"
  prov="$(echo "$d" | python3 -c "import sys,json;print(json.load(sys.stdin).get('meta',{}).get('provisioned'))" 2>/dev/null || echo True)"
  if [ "$prov" = "False" ]; then echo "$d" > "${tmp}/${uid}.json"; count=$((count+1)); fi
done

if [ "$count" -gt 0 ]; then
  tar czf - -C "${tmp}" . | aws s3 cp --sse AES256 - "s3://${BUCKET}/grafana/dashboards-${TS}.tgz"
  aws s3 cp --sse AES256 "s3://${BUCKET}/grafana/dashboards-${TS}.tgz" "s3://${BUCKET}/grafana/dashboards-latest.tgz"
  log "backed up ${count} hand-built dashboard(s) -> s3://${BUCKET}/grafana/dashboards-{${TS},latest}.tgz"
else
  log "no hand-built dashboards (all provisioned, recreated from ConfigMap on start) — nothing to back up"
fi
rm -rf "${tmp}"
