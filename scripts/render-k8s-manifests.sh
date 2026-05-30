#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="${1:-${ROOT_DIR}/.rendered-k8s}"

# shellcheck source=scripts/lib/env-aliases.sh
source "${ROOT_DIR}/scripts/lib/env-aliases.sh"

# Load local .env when present (never commit this file)
if [ -f "${ROOT_DIR}/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  source "${ROOT_DIR}/.env"
  set +a
  # shellcheck source=scripts/lib/env-aliases.sh
  source "${ROOT_DIR}/scripts/lib/env-aliases.sh"
fi

required=(
  K8S_NAMESPACE
  APP_ENV
  JWT_PUBLIC_KEY
  JWT_PRIVATE_KEY
  POSTGRES_PASSWORD
  MONGO_PASSWORD
  RABBITMQ_PASSWORD
)

missing=()
for key in "${required[@]}"; do
  if [ -z "${!key:-}" ]; then
    missing+=("$key")
  fi
done

if [ "${#missing[@]}" -gt 0 ]; then
  echo "ERROR: Missing required variables for K8s render: ${missing[*]}"
  echo "Set them in .env or export before running this script."
  exit 1
fi

_is_secret_manifest() {
  local file="$1"
  case "${file}" in
    */secrets/*|*/secret.yaml|*/rabbitmq-secret.yaml|*/grafana-secret.yaml)
      return 0
      ;;
  esac
  return 1
}

mkdir -p "${OUTPUT_DIR}"

echo "Rendering Kubernetes manifests to ${OUTPUT_DIR}..."

find "${ROOT_DIR}/infrastructure/kubernetes" \( -name '*.yaml' -o -name '*.yml' \) | while read -r file; do
  if _is_secret_manifest "${file}"; then
    continue
  fi
  rel="${file#"${ROOT_DIR}/"}"
  dest="${OUTPUT_DIR}/${rel}"
  mkdir -p "$(dirname "${dest}")"
  envsubst < "${file}" > "${dest}"
done

bash "${ROOT_DIR}/scripts/render-k8s-secrets.sh" "${OUTPUT_DIR}"

echo "Rendered manifests ready in ${OUTPUT_DIR}"
