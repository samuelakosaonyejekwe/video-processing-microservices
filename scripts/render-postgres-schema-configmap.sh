#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="${1:?output directory required}"

# shellcheck source=scripts/lib/env-aliases.sh
source "${ROOT_DIR}/scripts/lib/env-aliases.sh"

SCHEMA_FILE="${ROOT_DIR}/databases/postgresql/schema.sql"
DEST="${OUTPUT_DIR}/infrastructure/kubernetes/postgres/postgres-schema-configmap.yaml"

if [ ! -f "${SCHEMA_FILE}" ]; then
  echo "ERROR: Missing postgres schema source at ${SCHEMA_FILE}"
  exit 1
fi

mkdir -p "$(dirname "${DEST}")"

{
  cat <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: postgres-schema
  namespace: ${K8S_NAMESPACE}
  labels:
    app: postgres-migrations
data:
  schema.sql: |
EOF
  sed 's/^/    /' "${SCHEMA_FILE}"
} > "${DEST}"

echo "Rendered postgres schema ConfigMap from ${SCHEMA_FILE}"
