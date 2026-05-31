#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="${1:-${ROOT_DIR}/.rendered-k8s}"

# shellcheck source=scripts/lib/env-aliases.sh
source "${ROOT_DIR}/scripts/lib/env-aliases.sh"

# Load local .env when present (never commit this file)
if [ -f "${ROOT_DIR}/.env" ]; then
  set +u
  set -a
  # shellcheck disable=SC1091
  source "${ROOT_DIR}/.env"
  set +a
  set -u
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

if [ -z "${AWS_ACCOUNT_ID:-}" ] && command -v aws >/dev/null 2>&1; then
  export AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text 2>/dev/null || true)"
fi

# shellcheck source=scripts/resolve-ecr-registry.sh
source "${ROOT_DIR}/scripts/resolve-ecr-registry.sh"

_is_generated_manifest() {
  local file="$1"
  case "${file}" in
    */secrets/*|*/secret.yaml|*/rabbitmq-secret.yaml|*/grafana-secret.yaml|*/postgres/postgres-schema-configmap.yaml)
      return 0
      ;;
  esac
  return 1
}

_is_secret_manifest() {
  _is_generated_manifest "$1"
}

mkdir -p "${OUTPUT_DIR}"

echo "Rendering Kubernetes manifests to ${OUTPUT_DIR}..."

find "${ROOT_DIR}/infrastructure/kubernetes" \( -name '*.yaml' -o -name '*.yml' \) | while read -r file; do
  if _is_generated_manifest "${file}"; then
    continue
  fi
  rel="${file#"${ROOT_DIR}/"}"
  dest="${OUTPUT_DIR}/${rel}"
  mkdir -p "$(dirname "${dest}")"
  envsubst < "${file}" > "${dest}"
done

bash "${ROOT_DIR}/scripts/render-k8s-secrets.sh" "${OUTPUT_DIR}"
bash "${ROOT_DIR}/scripts/render-postgres-schema-configmap.sh" "${OUTPUT_DIR}"

_strip_ingress_tls() {
  local file="$1"
  local cert_var="$2"
  if [ -f "${file}" ] && { [ -z "${!cert_var:-}" ] || [[ "${!cert_var}" == *"placeholder"* ]]; }; then
    sed -i '/certificate-arn/d;/ssl-redirect/d' "${file}"
  fi
}

_strip_ingress_tls "${OUTPUT_DIR}/infrastructure/kubernetes/gateway/ingress.yaml" ACM_CERTIFICATE_ARN
_strip_ingress_tls "${OUTPUT_DIR}/infrastructure/kubernetes/frontend/ingress.yaml" FRONTEND_ACM_CERTIFICATE_ARN

echo "Rendered manifests ready in ${OUTPUT_DIR}"
