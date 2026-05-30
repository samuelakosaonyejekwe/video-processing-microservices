#!/bin/bash
# Expose cluster services to the CI runner via ingress/LB URL or kubectl port-forward.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/env-aliases.sh
source "${ROOT_DIR}/scripts/lib/env-aliases.sh"

PRODUCTION_TEST_PF_PIDS=()

cleanup_production_test_endpoints() {
  local pid
  for pid in "${PRODUCTION_TEST_PF_PIDS[@]}"; do
    kill "${pid}" 2>/dev/null || true
  done
  PRODUCTION_TEST_PF_PIDS=()
}

_start_port_forward() {
  local service="$1"
  local local_port="$2"
  local remote_port="${3:-80}"

  kubectl port-forward -n "${K8S_NAMESPACE}" "svc/${service}" \
    "${local_port}:${remote_port}" >/dev/null 2>&1 &
  PRODUCTION_TEST_PF_PIDS+=("$!")
}

_wait_for_http() {
  local url="$1"
  local attempt

  for attempt in $(seq 1 45); do
    if curl -sf "${url}" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done

  echo "ERROR: Timed out waiting for ${url}" >&2
  return 1
}

setup_production_test_endpoints() {
  local gateway_port="${PRODUCTION_TEST_GATEWAY_PORT:-18080}"
  local auth_port="${PRODUCTION_TEST_AUTH_PORT:-18000}"
  local converter_port="${PRODUCTION_TEST_CONVERTER_PORT:-18002}"
  local gateway_url=""

  gateway_url=""
  if discovered_url="$(bash "${ROOT_DIR}/scripts/discover-production-api-url.sh" 2>/dev/null)"; then
    gateway_url="${discovered_url}"
  fi

  if [ -z "${gateway_url}" ]; then
    echo "External gateway URL unavailable; using kubectl port-forward for gateway-service..."
    _start_port_forward "${GATEWAY_SERVICE_NAME:-gateway-service}" "${gateway_port}" 80
    gateway_url="http://127.0.0.1:${gateway_port}"
    _wait_for_http "${gateway_url}/health"
  else
    echo "Using discovered gateway URL: ${gateway_url}"
    _wait_for_http "${gateway_url}/health"
  fi

  echo "Starting kubectl port-forward for auth-service on 127.0.0.1:${auth_port}..."
  _start_port_forward "${AUTH_APP_NAME:-auth-service}" "${auth_port}" 80
  _wait_for_http "http://127.0.0.1:${auth_port}/health"

  echo "Starting kubectl port-forward for converter-service on 127.0.0.1:${converter_port}..."
  _start_port_forward "${CONVERTER_APP_NAME:-converter-service}" "${converter_port}" 80
  _wait_for_http "http://127.0.0.1:${converter_port}/health"

  export GATEWAY_BASE_URL="${gateway_url}"
  export AUTH_BASE_URL="http://127.0.0.1:${auth_port}"
  export CONVERTER_BASE_URL="http://127.0.0.1:${converter_port}"

  echo "Production test endpoints:"
  echo "  GATEWAY_BASE_URL=${GATEWAY_BASE_URL}"
  echo "  AUTH_BASE_URL=${AUTH_BASE_URL}"
  echo "  CONVERTER_BASE_URL=${CONVERTER_BASE_URL}"
}
