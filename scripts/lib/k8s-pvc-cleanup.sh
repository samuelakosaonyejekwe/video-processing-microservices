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

wait_for_pvc_bound() {
  local pvc="$1"
  local namespace="$2"
  local timeout_seconds="${3:-600}"

  if ! kubectl get pvc "${pvc}" -n "${namespace}" >/dev/null 2>&1; then
    echo "PVC ${pvc} not found in ${namespace}." >&2
    return 1
  fi

  echo "Waiting for PVC ${pvc} to bind in ${namespace}..."
  kubectl wait --for=jsonpath='{.status.phase}'=Bound \
    "pvc/${pvc}" \
    -n "${namespace}" \
    --timeout="${timeout_seconds}s"
}

scale_statefulset_to_zero() {
  local release="$1"
  local namespace="$2"
  local timeout_seconds="${3:-180}"

  if ! kubectl get "statefulset/${release}" -n "${namespace}" >/dev/null 2>&1; then
    return 0
  fi

  echo "Scaling ${release} to 0 in ${namespace}..."
  kubectl scale "statefulset/${release}" -n "${namespace}" --replicas=0
  kubectl wait --for=delete "pod/${release}-0" -n "${namespace}" --timeout="${timeout_seconds}s" 2>/dev/null \
    || kubectl wait --for=delete pod \
      -l "app=${release}" \
      -n "${namespace}" \
      --timeout="${timeout_seconds}s" 2>/dev/null \
    || true
}

scale_statefulset_to_one() {
  local release="$1"
  local namespace="$2"
  local timeout_seconds="${3:-600}"

  echo "Scaling ${release} to 1 in ${namespace}..."
  kubectl scale "statefulset/${release}" -n "${namespace}" --replicas=1
  kubectl rollout status "statefulset/${release}" -n "${namespace}" --timeout="${timeout_seconds}s"
}

prepare_mongodb_storage_for_helm() {
  local namespace="$1"

  if kubectl get pvc mongodb-pvc -n "${namespace}" >/dev/null 2>&1; then
    local phase
    phase="$(kubectl get pvc mongodb-pvc -n "${namespace}" -o jsonpath='{.status.phase}' 2>/dev/null || echo "")"
    if [ "${phase}" = "Bound" ]; then
      return 0
    fi

    if kubectl get pvc mongodb-pvc -n "${namespace}" -o jsonpath='{.metadata.deletionTimestamp}' 2>/dev/null | grep -q .; then
      wait_for_pvc_removal mongodb-pvc "${namespace}" 300
    fi
  fi

  scale_statefulset_to_zero mongodb "${namespace}" 180
}

finalize_mongodb_storage_after_helm() {
  local namespace="$1"

  if ! kubectl get pvc mongodb-pvc -n "${namespace}" >/dev/null 2>&1; then
    echo "MongoDB PVC not found after Helm upgrade." >&2
    return 1
  fi

  scale_statefulset_to_one mongodb "${namespace}" 600
  wait_for_pvc_bound mongodb-pvc "${namespace}" 600
}
