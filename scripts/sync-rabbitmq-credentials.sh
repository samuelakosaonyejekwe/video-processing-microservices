#!/bin/bash
# Align live RabbitMQ credentials with rendered secrets (PVC keeps init credentials).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/env-aliases.sh
source "${ROOT_DIR}/scripts/lib/env-aliases.sh"

pod="${RABBITMQ_RELEASE_NAME:-rabbitmq}-0"
namespace="${MESSAGING_NAMESPACE:-messaging}"
username="${RABBITMQ_USERNAME:-${RABBITMQ_DEFAULT_USER:-guest}}"
password="${RABBITMQ_PASSWORD:-${RABBITMQ_DEFAULT_PASS:-guest}}"

if ! kubectl get pod "${pod}" -n "${namespace}" >/dev/null 2>&1; then
  echo "RabbitMQ pod ${pod} not found in ${namespace}; skipping credential sync."
  exit 0
fi

if ! kubectl wait --for=condition=ready "pod/${pod}" -n "${namespace}" --timeout=180s >/dev/null 2>&1; then
  echo "RabbitMQ pod ${pod} not ready; skipping credential sync."
  exit 0
fi

escaped_password="$(printf '%s' "${password}" | sed "s/'/'\"'\"'/g")"

echo "Syncing RabbitMQ credentials for user ${username} in ${namespace}..."
kubectl exec -n "${namespace}" "${pod}" -- rabbitmqctl await_startup >/dev/null

if kubectl exec -n "${namespace}" "${pod}" -- rabbitmqctl list_users -q 2>/dev/null | awk '{print $1}' | grep -Fxq "${username}"; then
  kubectl exec -n "${namespace}" "${pod}" -- sh -c \
    "rabbitmqctl change_password '${username}' '${escaped_password}'"
else
  kubectl exec -n "${namespace}" "${pod}" -- sh -c \
    "rabbitmqctl add_user '${username}' '${escaped_password}' && rabbitmqctl set_user_tags '${username}' administrator && rabbitmqctl set_permissions -p / '${username}' '.*' '.*' '.*'"
fi

echo "RabbitMQ credentials synced."
