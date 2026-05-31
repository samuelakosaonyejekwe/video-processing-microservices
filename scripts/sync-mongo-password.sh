#!/bin/bash
# Align the live MongoDB user password with the app secret applied to the cluster.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/env-aliases.sh
source "${ROOT_DIR}/scripts/lib/env-aliases.sh"
# shellcheck source=scripts/lib/secret-sanitize.sh
source "${ROOT_DIR}/scripts/lib/secret-sanitize.sh"
# shellcheck source=scripts/lib/k8s-pvc-cleanup.sh
source "${ROOT_DIR}/scripts/lib/k8s-pvc-cleanup.sh"

pod="${MONGODB_RELEASE_NAME:-mongodb}-0"
db_namespace="${DATABASE_NAMESPACE:-database}"
app_namespace="${K8S_NAMESPACE:-video-processing}"
secret_name="mongodb-secret"

if ! kubectl get pod "${pod}" -n "${db_namespace}" >/dev/null 2>&1; then
  echo "MongoDB pod ${pod} not found in ${db_namespace}; skipping password sync."
  exit 0
fi

if ! kubectl wait --for=condition=ready "pod/${pod}" -n "${db_namespace}" --timeout=120s >/dev/null 2>&1; then
  echo "MongoDB pod ${pod} not ready; skipping password sync."
  exit 0
fi

if kubectl get secret "${secret_name}" -n "${app_namespace}" >/dev/null 2>&1; then
  mongo_user="$(kubectl get secret "${secret_name}" -n "${app_namespace}" -o jsonpath='{.data.MONGO_USERNAME}' | base64 -d)"
  mongo_password="$(kubectl get secret "${secret_name}" -n "${app_namespace}" -o jsonpath='{.data.MONGO_PASSWORD}' | base64 -d)"
  mongo_database="$(kubectl get secret "${secret_name}" -n "${app_namespace}" -o jsonpath='{.data.MONGO_DATABASE}' | base64 -d)"
  mongo_auth_source="$(kubectl get secret "${secret_name}" -n "${app_namespace}" -o jsonpath='{.data.MONGO_AUTH_SOURCE}' | base64 -d)"
else
  sanitize_secret_env
  mongo_user="${MONGO_USERNAME:-mongo}"
  mongo_password="${MONGO_PASSWORD:-mongo}"
  mongo_database="${MONGO_DATABASE:-video_converter}"
  mongo_auth_source="${MONGO_AUTH_SOURCE:-admin}"
fi

if [ -z "${mongo_user}" ] || [ -z "${mongo_password}" ]; then
  echo "ERROR: MongoDB username/password unavailable for password sync." >&2
  exit 1
fi

mongo_auth_source="${mongo_auth_source:-admin}"
mongo_database="${mongo_database:-video_converter}"
password_b64="$(printf '%s' "${mongo_password}" | base64 -w0 2>/dev/null || printf '%s' "${mongo_password}" | base64)"

_mongo_auth_ok() {
  kubectl exec -n "${db_namespace}" "${pod}" -- sh -c \
    "mongosh 'mongodb://127.0.0.1:27017/${mongo_auth_source}' \
      -u '${mongo_user}' \
      -p \"\$(printf '%s' '${password_b64}' | base64 -d)\" \
      --quiet --eval 'db.runCommand({ping:1}).ok'" 2>/dev/null | grep -q '^1$'
}

_sync_password_in_mongo() {
  kubectl exec -n "${db_namespace}" "${pod}" -- sh -c \
    "mongosh 'mongodb://127.0.0.1:27017/${mongo_auth_source}' \
      -u '${mongo_user}' \
      -p \"\$(printf '%s' '${password_b64}' | base64 -d)\" \
      --quiet --eval \"
        const password = Buffer.from('${password_b64}', 'base64').toString();
        db.changeUserPassword('${mongo_user}', password);
        if ('${mongo_database}' !== '${mongo_auth_source}') {
          db.getSiblingDB('${mongo_database}').changeUserPassword('${mongo_user}', password);
        }
      \"" >/dev/null 2>&1
}

_reset_mongo_data() {
  echo "WARNING: Resetting MongoDB data volume to align credentials."
  echo "WARNING: Existing conversion job history in MongoDB will be lost."

  kubectl delete pod "${pod}" -n "${db_namespace}" --ignore-not-found --wait=false
  delete_pvc_and_wait mongodb-pvc "${db_namespace}" 300

  helm_dir="${ROOT_DIR}/.rendered-helm/infrastructure/helm"
  global_values="${helm_dir}/global-values.yaml"
  if [ ! -d "${helm_dir}/mongodb" ]; then
    bash "${ROOT_DIR}/scripts/render-helm-charts.sh" "${ROOT_DIR}/.rendered-helm"
  fi

  echo "Recreating MongoDB storage and waiting for pod readiness..."
  scale_statefulset_to_zero "${MONGODB_RELEASE_NAME:-mongodb}" "${db_namespace}" 180

  helm upgrade --install "${MONGODB_RELEASE_NAME:-mongodb}" "${helm_dir}/mongodb" \
    --namespace "${db_namespace}" \
    -f "${global_values}" \
    --timeout 20m

  finalize_mongodb_storage_after_helm "${db_namespace}"
}

if _mongo_auth_ok; then
  echo "MongoDB credentials already aligned for user ${mongo_user}."
  exit 0
fi

echo "Syncing MongoDB password for user ${mongo_user} in ${db_namespace}..."

if _sync_password_in_mongo && _mongo_auth_ok; then
  echo "MongoDB password synced."
  exit 0
fi

echo "MongoDB password change with current credentials failed; reinitializing data volume..."
_reset_mongo_data

if ! _mongo_auth_ok; then
  echo "ERROR: MongoDB password sync failed for user ${mongo_user} after PVC reset." >&2
  exit 1
fi

echo "MongoDB password synced after data volume reset."
