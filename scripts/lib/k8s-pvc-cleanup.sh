#!/bin/bash
# Helpers for deleting PVCs that get stuck in Terminating during redeploys.

wait_for_pvc_removal() {
  local pvc="$1"
  local namespace="$2"
  local timeout_seconds="${3:-300}"

  if ! kubectl get pvc "${pvc}" -n "${namespace}" >/dev/null 2>&1; then
    return 0
  fi

  echo "Waiting for PVC ${pvc} removal in ${namespace}..."
  local deadline=$((SECONDS + timeout_seconds))

  while kubectl get pvc "${pvc}" -n "${namespace}" >/dev/null 2>&1; do
    if [ "${SECONDS}" -ge "${deadline}" ]; then
      echo "PVC ${pvc} still present after ${timeout_seconds}s; clearing finalizers..." >&2
      kubectl patch pvc "${pvc}" -n "${namespace}" \
        -p '{"metadata":{"finalizers":null}}' \
        --type=merge >/dev/null 2>&1 || true
      kubectl delete pvc "${pvc}" -n "${namespace}" --ignore-not-found --wait=true || true
      break
    fi

    if [ $((SECONDS + 60)) -ge "${deadline}" ]; then
      echo "PVC ${pvc} still terminating; attempting finalizer cleanup..." >&2
      kubectl patch pvc "${pvc}" -n "${namespace}" \
        -p '{"metadata":{"finalizers":null}}' \
        --type=merge >/dev/null 2>&1 || true
    fi

    sleep 5
  done

  if kubectl get pvc "${pvc}" -n "${namespace}" >/dev/null 2>&1; then
    echo "ERROR: PVC ${pvc} could not be removed from ${namespace}." >&2
    return 1
  fi

  echo "PVC ${pvc} removed from ${namespace}."
}

delete_pvc_and_wait() {
  local pvc="$1"
  local namespace="$2"
  local timeout_seconds="${3:-300}"

  kubectl delete pvc "${pvc}" -n "${namespace}" --ignore-not-found --wait=false 2>/dev/null || true
  wait_for_pvc_removal "${pvc}" "${namespace}" "${timeout_seconds}"
}
