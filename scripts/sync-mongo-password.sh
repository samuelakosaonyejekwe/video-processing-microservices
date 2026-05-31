#!/bin/bash
# Align the live MongoDB user password with the app secret applied to the cluster.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/env-aliases.sh
source "${ROOT_DIR}/scripts/lib/env-aliases.sh"
# shellcheck source=scripts/lib/secret-sanitize.sh
source "${ROOT_DIR}/scripts/lib/secret-sanitize.sh"

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

if _mongo_auth_ok; then
  echo "MongoDB credentials already aligned for user ${mongo_user}."
  exit 0
fi

echo "Syncing MongoDB password for user ${mongo_user} in ${db_namespace}..."

kubectl exec -n "${db_namespace}" "${pod}" -- sh -c \
  "mongosh --quiet <<'EOSQL'
const password = Buffer.from('${password_b64}', 'base64').toString();
const user = '${mongo_user}';
const adminDb = db.getSiblingDB('${mongo_auth_source}');
const appDb = db.getSiblingDB('${mongo_database}');

function ensureAdminPassword(database) {
  try {
    database.changeUserPassword(user, password);
    print('Updated password for ' + user + ' in ' + database.getName());
  } catch (error) {
    if (String(error).includes('UserNotFound')) {
      database.createUser({
        user: user,
        pwd: password,
        roles: [{ role: 'root', db: 'admin' }],
      });
      print('Created admin user ' + user);
    } else {
      throw error;
    }
  }
}

function ensureAppPassword(database) {
  try {
    database.changeUserPassword(user, password);
    print('Updated password for ' + user + ' in ' + database.getName());
  } catch (error) {
    if (String(error).includes('UserNotFound')) {
      database.createUser({
        user: user,
        pwd: password,
        roles: [{ role: 'readWrite', db: database.getName() }],
      });
      print('Created user ' + user + ' in ' + database.getName());
    } else {
      throw error;
    }
  }
}

ensureAdminPassword(adminDb);
if ('${mongo_database}' !== '${mongo_auth_source}') {
  ensureAppPassword(appDb);
}
EOSQL"

if ! _mongo_auth_ok; then
  echo "ERROR: MongoDB password sync failed for user ${mongo_user}." >&2
  exit 1
fi

echo "MongoDB password synced."
