#!/bin/bash
# restore-rabbitmq.sh — Restore RabbitMQ from the latest S3 backup after a full
# recreate. Imports definitions (topology) ALWAYS, and optionally restores the
# mnesia message store.
#
#   definitions  -> rabbitmqctl import_definitions  (idempotent topology restore)
#   messages     -> stop_app, replace mnesia, start_app  (RESTORE_RABBITMQ_MESSAGES,
#                   default true). Node name is stable (StatefulSet rabbitmq-0), so
#                   the on-disk store reloads on the recreated single node.
#
# Env: DATABASE_BACKUP_BUCKET, kubectl context, AWS creds.
#      RABBITMQ_NAMESPACE (default messaging), RESTORE_RABBITMQ=true/false,
#      RESTORE_RABBITMQ_MESSAGES=true/false.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/env-aliases.sh
source "${ROOT_DIR}/scripts/lib/env-aliases.sh"

log() { echo "[$(date -u '+%H:%M:%S')] restore-rabbitmq: $*"; }
warn() { echo "[$(date -u '+%H:%M:%S')] restore-rabbitmq: WARNING: $*" >&2; }

if [ "${RESTORE_RABBITMQ:-true}" != "true" ]; then
  log "RESTORE_RABBITMQ=${RESTORE_RABBITMQ:-} — skipping."
  exit 0
fi

: "${DATABASE_BACKUP_BUCKET:?Missing DATABASE_BACKUP_BUCKET}"
BUCKET="${DATABASE_BACKUP_BUCKET}"
NS="${RABBITMQ_NAMESPACE:-messaging}"
RESTORE_MSGS="${RESTORE_RABBITMQ_MESSAGES:-true}"

POD="$(kubectl -n "${NS}" get pods -l app.kubernetes.io/name=rabbitmq -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
[ -n "${POD}" ] || POD="$(kubectl -n "${NS}" get pods -o name 2>/dev/null | grep -i rabbitmq | head -1 | sed 's#pod/##')"
[ -n "${POD}" ] || { echo "ERROR: no RabbitMQ pod in ns ${NS}." >&2; exit 1; }
kubectl -n "${NS}" wait --for=condition=ready "pod/${POD}" --timeout=180s >/dev/null 2>&1 || true
log "RabbitMQ pod: ${NS}/${POD}"

# --- 1) messages (mnesia) — do BEFORE definitions so import tops up topology after ---
if [ "${RESTORE_MSGS}" = "true" ] && aws s3 ls "s3://${BUCKET}/rabbitmq/mnesia-latest.tgz" >/dev/null 2>&1; then
  log "Restoring mnesia message store..."
  kubectl -n "${NS}" exec "${POD}" -- rabbitmqctl stop_app || true
  # wipe current mnesia then stream the backup straight in
  kubectl -n "${NS}" exec "${POD}" -- sh -c 'rm -rf /var/lib/rabbitmq/mnesia/* 2>/dev/null || true'
  if aws s3 cp "s3://${BUCKET}/rabbitmq/mnesia-latest.tgz" - \
       | kubectl -n "${NS}" exec -i "${POD}" -- tar xzf - -C /var/lib/rabbitmq; then
    log "mnesia data restored."
  else
    warn "mnesia restore stream failed — continuing with a fresh store (definitions will still import)."
  fi
  kubectl -n "${NS}" exec "${POD}" -- rabbitmqctl start_app || \
    warn "start_app reported an error — check 'rabbitmqctl status' in the pod."
else
  [ "${RESTORE_MSGS}" = "true" ] && log "No mnesia-latest.tgz found — skipping message restore (topology only)."
fi

# --- 2) definitions (topology) — always, idempotent ---
if aws s3 ls "s3://${BUCKET}/rabbitmq/definitions-latest.json" >/dev/null 2>&1; then
  log "Importing definitions..."
  if aws s3 cp "s3://${BUCKET}/rabbitmq/definitions-latest.json" - \
       | kubectl -n "${NS}" exec -i "${POD}" -- sh -c 'cat > /tmp/rmq-defs.json && rabbitmqctl import_definitions /tmp/rmq-defs.json && rm -f /tmp/rmq-defs.json'; then
    log "Definitions imported."
  else
    warn "import_definitions failed — queues may be recreated by the apps on first connect."
  fi
else
  warn "No definitions-latest.json in s3://${BUCKET}/rabbitmq/ — nothing to import."
fi

log "DONE."
