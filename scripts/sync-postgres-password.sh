#!/bin/bash
# Align the live PostgreSQL role password with the rendered secret (PVC keeps init password).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/env-aliases.sh
source "${ROOT_DIR}/scripts/lib/env-aliases.sh"

pod="${POSTGRESQL_RELEASE_NAME:-postgresql}-0"
namespace="${DATABASE_NAMESPACE:-database}"

if ! kubectl get pod "${pod}" -n "${namespace}" >/dev/null 2>&1; then
  echo "PostgreSQL pod ${pod} not found in ${namespace}; skipping password sync."
  exit 0
fi

if ! kubectl wait --for=condition=ready "pod/${pod}" -n "${namespace}" --timeout=120s >/dev/null 2>&1; then
  echo "PostgreSQL pod ${pod} not ready; skipping password sync."
  exit 0
fi

escaped_password="$(printf '%s' "${POSTGRES_PASSWORD}" | sed "s/'/''/g")"

echo "Syncing PostgreSQL password for user ${POSTGRES_USER} in ${namespace}..."
kubectl exec -n "${namespace}" "${pod}" -- \
  psql -v ON_ERROR_STOP=1 -U "${POSTGRES_USER}" -d postgres \
  -c "ALTER USER \"${POSTGRES_USER}\" WITH PASSWORD '${escaped_password}';"

echo "PostgreSQL password synced."
