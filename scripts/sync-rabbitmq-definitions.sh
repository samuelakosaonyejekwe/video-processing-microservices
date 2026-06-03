#!/bin/bash
# Import rendered RabbitMQ queue/exchange definitions without a full Helm upgrade.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/env-aliases.sh
source "${ROOT_DIR}/scripts/lib/env-aliases.sh"

if [ "${SYNC_RABBITMQ_DEFINITIONS:-true}" != "true" ]; then
  echo "Skipping RabbitMQ definition sync (SYNC_RABBITMQ_DEFINITIONS=false)."
  exit 0
fi

pod="${RABBITMQ_RELEASE_NAME:-rabbitmq}-0"
broker_namespace="${MESSAGING_NAMESPACE:-messaging}"
definitions_template="${ROOT_DIR}/messaging/rabbitmq/definitions.json"
rendered_definitions="${ROOT_DIR}/.rendered-k8s/rabbitmq-definitions.json"

if [ ! -f "${definitions_template}" ]; then
  echo "RabbitMQ definitions template missing; skipping sync."
  exit 0
fi

if ! kubectl get pod "${pod}" -n "${broker_namespace}" >/dev/null 2>&1; then
  echo "RabbitMQ pod ${pod} not found; skipping definition sync."
  exit 0
fi

if ! kubectl wait --for=condition=ready "pod/${pod}" -n "${broker_namespace}" --timeout=120s >/dev/null 2>&1; then
  echo "RabbitMQ pod ${pod} not ready; skipping definition sync."
  exit 0
fi

mkdir -p "$(dirname "${rendered_definitions}")"
envsubst < "${definitions_template}" > "${rendered_definitions}"

echo "Syncing RabbitMQ definitions into ${broker_namespace}/${pod}..."
kubectl cp "${rendered_definitions}" "${broker_namespace}/${pod}:/tmp/rabbitmq-definitions.json"
if kubectl exec -n "${broker_namespace}" "${pod}" -- sh -c \
  "rabbitmqctl await_startup >/dev/null && rabbitmqctl import_definitions /tmp/rabbitmq-definitions.json"; then
  echo "RabbitMQ definitions synced."
else
  echo "WARNING: RabbitMQ definition import failed; runtime queue declarations will continue to apply topology." >&2
fi
