#!/bin/bash
# Render Helm chart values with envsubst before install.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="${1:-${ROOT_DIR}/.rendered-helm}"

# shellcheck source=scripts/lib/env-aliases.sh
source "${ROOT_DIR}/scripts/lib/env-aliases.sh"

_yaml_safe() {
  printf '%s' "${1}" | tr -d '\000-\010\013\014\016-\037' | sed 's/"/\\"/g'
}

for key in RABBITMQ_PASSWORD RABBITMQ_USERNAME RABBITMQ_ERLANG_COOKIE \
  POSTGRES_PASSWORD POSTGRES_USER MONGO_PASSWORD MONGO_USERNAME; do
  if [ -n "${!key:-}" ]; then
    export "${key}=$(_yaml_safe "${!key}")"
  fi
done

render_chart() {
  local rel_src="$1"
  local src="${ROOT_DIR}/${rel_src}"
  local dest="${OUTPUT_DIR}/${rel_src}"

  mkdir -p "${dest}/templates"

  if [ -f "${src}/Chart.yaml" ]; then
    cp "${src}/Chart.yaml" "${dest}/Chart.yaml"
  fi

  for file in "${src}"/*.yaml "${src}"/*.yml; do
    [ -f "$file" ] || continue
    envsubst < "$file" > "${dest}/$(basename "$file")"
  done

  if [ -d "${src}/templates" ]; then
    cp -r "${src}/templates/." "${dest}/templates/"
  fi
}

rm -rf "${OUTPUT_DIR}/infrastructure/helm"
mkdir -p "${OUTPUT_DIR}/infrastructure/helm"

for chart in mongodb postgresql rabbitmq; do
  render_chart "infrastructure/helm/${chart}"
done

envsubst < "${ROOT_DIR}/infrastructure/helm/global-values.yaml" \
  > "${OUTPUT_DIR}/infrastructure/helm/global-values.yaml"

echo "Rendered Helm charts to ${OUTPUT_DIR}"
