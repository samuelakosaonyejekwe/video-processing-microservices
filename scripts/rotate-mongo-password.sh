#!/bin/bash
# Safely rotate the MongoDB user password WITHOUT data loss.
#
# changeUserPassword requires authenticating with the CURRENT password, so this
# script needs the old password as input. It authenticates with the old
# password, sets the new one (on the auth-source DB and the app DB), updates the
# Kubernetes `mongodb-secret` in both the database and app namespaces, and
# verifies the new password works.
#
# The NEW password is taken from MONGO_PASSWORD (the single source of truth,
# normally the MONGO_PASSWORD GitHub secret). The OLD password must be supplied
# via MONGO_OLD_PASSWORD.
#
#   MONGO_OLD_PASSWORD=<current-live-pw> MONGO_PASSWORD=<new-pw> \
#     scripts/rotate-mongo-password.sh
#
# After running, also update the MONGO_PASSWORD GitHub secret (if the new value
# is not already there) so future renders/deploys stay aligned.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/env-aliases.sh
source "${ROOT_DIR}/scripts/lib/env-aliases.sh"

pod="${MONGODB_RELEASE_NAME:-mongodb}-0"
db_namespace="${DATABASE_NAMESPACE:-database}"
app_namespace="${K8S_NAMESPACE:-video-processing}"
secret_name="mongodb-secret"

mongo_user="${MONGO_USERNAME:-mongo}"
mongo_database="${MONGO_DATABASE:-video_converter}"
mongo_auth_source="${MONGO_AUTH_SOURCE:-admin}"
new_password="${MONGO_PASSWORD:?ERROR: MONGO_PASSWORD (new password) must be set}"
old_password="${MONGO_OLD_PASSWORD:?ERROR: MONGO_OLD_PASSWORD (current live password) must be set}"

# Same injection guards as sync-mongo-password.sh.
for v in mongo_user mongo_database mongo_auth_source; do
  if ! [[ "${!v}" =~ ^[a-zA-Z0-9_]+$ ]]; then
    echo "ERROR: ${v}='${!v}' contains invalid characters. Aborting." >&2
    exit 1
  fi
done

old_b64="$(printf '%s' "${old_password}" | base64 -w0)"
new_b64="$(printf '%s' "${new_password}" | base64 -w0)"

_auth_ok() { # $1 = base64 password
  kubectl exec -n "${db_namespace}" "${pod}" -- sh -c \
    "mongosh 'mongodb://127.0.0.1:27017/${mongo_auth_source}' -u '${mongo_user}' \
      -p \"\$(printf '%s' '$1' | base64 -d)\" --quiet --eval 'db.runCommand({ping:1}).ok'" \
    2>/dev/null | grep -q '^1$'
}

if _auth_ok "${new_b64}"; then
  echo "MongoDB already accepts the new password for user '${mongo_user}'. Nothing to rotate."
else
  if ! _auth_ok "${old_b64}"; then
    echo "ERROR: Could not authenticate with MONGO_OLD_PASSWORD. Provide the correct current password." >&2
    exit 1
  fi
  echo "Rotating MongoDB password for user '${mongo_user}' (authenticating with the old password)..."
  kubectl exec -n "${db_namespace}" "${pod}" -- sh -c \
    "mongosh 'mongodb://127.0.0.1:27017/${mongo_auth_source}' -u '${mongo_user}' \
      -p \"\$(printf '%s' '${old_b64}' | base64 -d)\" --quiet --eval \"
        const password = Buffer.from('${new_b64}', 'base64').toString();
        db.changeUserPassword('${mongo_user}', password);
        if ('${mongo_database}' !== '${mongo_auth_source}') {
          db.getSiblingDB('${mongo_database}').changeUserPassword('${mongo_user}', password);
        }
      \"" >/dev/null
  if ! _auth_ok "${new_b64}"; then
    echo "ERROR: New password not accepted after changeUserPassword. Aborting before touching secrets." >&2
    exit 1
  fi
  echo "MongoDB user password changed successfully."
fi

# Align the Kubernetes secrets in both namespaces so the app + server agree.
for ns in "${db_namespace}" "${app_namespace}"; do
  if kubectl get secret "${secret_name}" -n "${ns}" >/dev/null 2>&1; then
    kubectl patch secret "${secret_name}" -n "${ns}" --type merge \
      -p "{\"data\":{\"MONGO_PASSWORD\":\"${new_b64}\"}}" >/dev/null
    echo "Updated ${secret_name} MONGO_PASSWORD in namespace ${ns}."
  fi
done

echo "Done. Restart app pods that cache the connection if needed, and ensure the"
echo "MONGO_PASSWORD GitHub secret matches the new value for future deploys."
