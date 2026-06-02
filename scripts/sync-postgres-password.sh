#!/bin/bash
# Align the live PostgreSQL role password with the app secret applied to the cluster.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/env-aliases.sh
source "${ROOT_DIR}/scripts/lib/env-aliases.sh"

pod="${POSTGRESQL_RELEASE_NAME:-postgresql}-0"
db_namespace="${DATABASE_NAMESPACE:-database}"
app_namespace="${K8S_NAMESPACE:-video-processing}"
secret_name="${POSTGRES_APP_SECRET_NAME:-postgres-secret}"

if ! kubectl get pod "${pod}" -n "${db_namespace}" >/dev/null 2>&1; then
  echo "PostgreSQL pod ${pod} not found in ${db_namespace}; skipping password sync."
  exit 0
fi

if ! kubectl wait --for=condition=ready "pod/${pod}" -n "${db_namespace}" --timeout=120s >/dev/null 2>&1; then
  echo "PostgreSQL pod ${pod} not ready; skipping password sync."
  exit 0
fi

if kubectl get secret "${secret_name}" -n "${app_namespace}" >/dev/null 2>&1; then
  postgres_user="$(kubectl get secret "${secret_name}" -n "${app_namespace}" -o jsonpath='{.data.POSTGRES_USER}' | base64 -d)"
  postgres_password="$(kubectl get secret "${secret_name}" -n "${app_namespace}" -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 -d)"
else
  postgres_user="${POSTGRES_USER:-postgres}"
  postgres_password="${POSTGRES_PASSWORD:?ERROR: POSTGRES_PASSWORD must be set}"
fi

if [ -z "${postgres_user}" ] || [ -z "${postgres_password}" ]; then
  echo "ERROR: PostgreSQL username/password unavailable for password sync." >&2
  exit 1
fi

# Guard against shell/SQL injection: PostgreSQL usernames are alphanumeric + underscore only.
if ! [[ "${postgres_user}" =~ ^[a-zA-Z0-9_]+$ ]]; then
  echo "ERROR: PostgreSQL username '${postgres_user}' contains invalid characters. Aborting." >&2
  exit 1
fi

password_b64="$(printf '%s' "${postgres_password}" | base64 -w0 2>/dev/null || printf '%s' "${postgres_password}" | base64)"

echo "Syncing PostgreSQL password for user ${postgres_user} in ${db_namespace}..."
kubectl exec -n "${db_namespace}" "${pod}" -- sh -c \
  "psql -v ON_ERROR_STOP=1 -U '${postgres_user}' -d postgres -c \"ALTER USER \\\"${postgres_user}\\\" WITH PASSWORD '\$(printf '%s' '${password_b64}' | base64 -d)';\""

echo "PostgreSQL password synced."
