#!/bin/bash
# Align live RabbitMQ credentials with the app secrets applied to the cluster.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/env-aliases.sh
source "${ROOT_DIR}/scripts/lib/env-aliases.sh"
# shellcheck source=scripts/lib/secret-sanitize.sh
source "${ROOT_DIR}/scripts/lib/secret-sanitize.sh"

pod="${RABBITMQ_RELEASE_NAME:-rabbitmq}-0"
broker_namespace="${MESSAGING_NAMESPACE:-messaging}"
app_namespace="${K8S_NAMESPACE:-video-processing}"
secret_name="${RABBITMQ_APP_SECRET_NAME:-rabbitmq-secret}"

if ! kubectl get pod "${pod}" -n "${broker_namespace}" >/dev/null 2>&1; then
  echo "RabbitMQ pod ${pod} not found in ${broker_namespace}; skipping credential sync."
  exit 0
fi

if ! kubectl wait --for=condition=ready "pod/${pod}" -n "${broker_namespace}" --timeout=180s >/dev/null 2>&1; then
  echo "RabbitMQ pod ${pod} not ready; skipping credential sync."
  exit 0
fi

if kubectl get secret "${secret_name}" -n "${app_namespace}" >/dev/null 2>&1; then
  username="$(kubectl get secret "${secret_name}" -n "${app_namespace}" -o jsonpath='{.data.RABBITMQ_USERNAME}' | base64 -d)"
  password="$(kubectl get secret "${secret_name}" -n "${app_namespace}" -o jsonpath='{.data.RABBITMQ_PASSWORD}' | base64 -d)"
else
  sanitize_secret_env
  username="${RABBITMQ_USERNAME:-${RABBITMQ_DEFAULT_USER:-guest}}"
  password="${RABBITMQ_PASSWORD:-${RABBITMQ_DEFAULT_PASS:-guest}}"
fi

if [ -z "${username}" ] || [ -z "${password}" ]; then
  echo "ERROR: RabbitMQ username/password unavailable for credential sync." >&2
  exit 1
fi

password_b64="$(printf '%s' "${password}" | base64 -w0 2>/dev/null || printf '%s' "${password}" | base64)"

echo "Syncing RabbitMQ credentials for user ${username} in ${broker_namespace}..."
kubectl exec -n "${broker_namespace}" "${pod}" -- rabbitmqctl await_startup >/dev/null

if kubectl exec -n "${broker_namespace}" "${pod}" -- rabbitmqctl list_users -q 2>/dev/null | awk '{print $1}' | grep -Fxq "${username}"; then
  kubectl exec -n "${broker_namespace}" "${pod}" -- sh -c \
    "rabbitmqctl change_password '${username}' \"\$(printf '%s' '${password_b64}' | base64 -d)\""
else
  kubectl exec -n "${broker_namespace}" "${pod}" -- sh -c \
    "rabbitmqctl add_user '${username}' \"\$(printf '%s' '${password_b64}' | base64 -d)\" && rabbitmqctl set_user_tags '${username}' administrator && rabbitmqctl set_permissions -p / '${username}' '.*' '.*' '.*'"
fi

echo "RabbitMQ credentials synced."
