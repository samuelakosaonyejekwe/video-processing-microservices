#!/bin/bash
# Assert video pipeline RabbitMQ queues are empty after validation.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/env-aliases.sh
source "${ROOT_DIR}/scripts/lib/env-aliases.sh"

MODE="${1:-k8s}"
COMPOSE_ENV_FILE="${COMPOSE_ENV_FILE:-.env.compose.runtime}"

_queue_count() {
  local queue="$1"

  if [ "${MODE}" = "compose" ]; then
    docker compose --env-file "${COMPOSE_ENV_FILE}" exec -T rabbitmq \
      rabbitmqctl list_queues name messages \
      | awk -v queue="${queue}" '$1 == queue { print $2 }'
    return
  fi

  local messaging_ns="${MESSAGING_NAMESPACE:-messaging}"
  kubectl exec -n "${messaging_ns}" rabbitmq-0 -- \
    rabbitmqctl list_queues name messages \
    | awk -v queue="${queue}" '$1 == queue { print $2 }'
}

for queue in video-upload-queue video-upload-retry-queue video-upload-dlq; do
  count="$(_queue_count "${queue}")"
  if [ "${count:-0}" != "0" ]; then
    echo "ERROR: Queue ${queue} has ${count} message(s)"
    exit 1
  fi
  echo "  ${queue}: ${count:-0}"
done
