#!/bin/bash
# backup-rabbitmq.sh — Back up RabbitMQ to S3 so a full-mode destroy (which
# deletes the rabbitmq PVC) loses no topology and no durable messages.
#
# Two artifacts:
#   definitions-*.json  — vhosts/exchanges/queues/bindings/users/policies (ALWAYS,
#                         online-safe). This is the guaranteed-restorable part.
#   mnesia-*.tgz        — the on-disk message store (durable/persistent messages).
#                         For a consistent copy we briefly `rabbitmqctl stop_app`
#                         (QUIESCE=true, the default for shutdown). Set QUIESCE=false
#                         for an online best-effort copy (used for non-disruptive tests).
#
# Practical loss is ~0 even if a message slips through: the app uses an outbox +
# job-id idempotency, so anything missed is re-published/deduped.
#
# Env: DATABASE_BACKUP_BUCKET, kubectl context, AWS creds.
#      RABBITMQ_NAMESPACE (default messaging), QUIESCE (default true),
#      SKIP_RABBITMQ_BACKUP=true to skip.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/env-aliases.sh
source "${ROOT_DIR}/scripts/lib/env-aliases.sh"

log() { echo "[$(date -u '+%H:%M:%S')] backup-rabbitmq: $*"; }

if [ "${SKIP_RABBITMQ_BACKUP:-false}" = "true" ]; then
  log "SKIP_RABBITMQ_BACKUP=true — skipping."
  exit 0
fi

: "${DATABASE_BACKUP_BUCKET:?Missing DATABASE_BACKUP_BUCKET}"
BUCKET="${DATABASE_BACKUP_BUCKET}"
NS="${RABBITMQ_NAMESPACE:-messaging}"
QUIESCE="${QUIESCE:-true}"
TS="$(date -u +%Y%m%d-%H%M%S)"
SSE=(--sse AES256)

# Resolve the pod (label first, then conventional name).
POD="$(kubectl -n "${NS}" get pods -l app.kubernetes.io/name=rabbitmq -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
[ -n "${POD}" ] || POD="$(kubectl -n "${NS}" get pods -o name 2>/dev/null | grep -i rabbitmq | head -1 | sed 's#pod/##')"
[ -n "${POD}" ] || { echo "ERROR: no RabbitMQ pod in ns ${NS}." >&2; exit 1; }
log "RabbitMQ pod: ${NS}/${POD} (QUIESCE=${QUIESCE})"

# Wait until the pod is actually scheduled and Ready before exec'ing into it.
# Full-mode shutdown may have just scaled worker nodes back up (from a prior soft
# shutdown), so the pod can still be Pending ("does not have a host assigned").
kubectl -n "${NS}" wait --for=condition=ready "pod/${POD}" --timeout=300s >/dev/null 2>&1 \
  || { echo "ERROR: RabbitMQ pod ${NS}/${POD} not Ready within timeout." >&2; exit 1; }

# --- 1) Definitions (topology) — online-safe, the guaranteed-restore artifact ---
log "Exporting definitions..."
kubectl -n "${NS}" exec "${POD}" -- rabbitmqctl export_definitions /tmp/rmq-defs.json >/dev/null
kubectl -n "${NS}" exec "${POD}" -- cat /tmp/rmq-defs.json \
  | aws s3 cp "${SSE[@]}" - "s3://${BUCKET}/rabbitmq/definitions-${TS}.json"
kubectl -n "${NS}" exec "${POD}" -- cat /tmp/rmq-defs.json \
  | aws s3 cp "${SSE[@]}" - "s3://${BUCKET}/rabbitmq/definitions-latest.json"
kubectl -n "${NS}" exec "${POD}" -- rm -f /tmp/rmq-defs.json 2>/dev/null || true
log "Definitions backed up -> s3://${BUCKET}/rabbitmq/definitions-{${TS},latest}.json"

# --- 2) Messages (mnesia data dir) ---
if [ "${QUIESCE}" = "true" ]; then
  log "Quiescing RabbitMQ (rabbitmqctl stop_app) for a consistent message snapshot..."
  kubectl -n "${NS}" exec "${POD}" -- rabbitmqctl stop_app
fi
# Always restart the app even if the copy fails.
restart_app() { [ "${QUIESCE}" = "true" ] && kubectl -n "${NS}" exec "${POD}" -- rabbitmqctl start_app || true; }
trap restart_app EXIT

log "Streaming mnesia data dir to S3..."
if kubectl -n "${NS}" exec "${POD}" -- tar czf - -C /var/lib/rabbitmq mnesia \
     | aws s3 cp "${SSE[@]}" - "s3://${BUCKET}/rabbitmq/mnesia-${TS}.tgz"; then
  # duplicate to 'latest'
  aws s3 cp "${SSE[@]}" "s3://${BUCKET}/rabbitmq/mnesia-${TS}.tgz" "s3://${BUCKET}/rabbitmq/mnesia-latest.tgz"
  log "Messages backed up -> s3://${BUCKET}/rabbitmq/mnesia-{${TS},latest}.tgz"
else
  echo "WARNING: mnesia copy failed; definitions are still backed up." >&2
fi

restart_app
trap - EXIT
log "DONE."
