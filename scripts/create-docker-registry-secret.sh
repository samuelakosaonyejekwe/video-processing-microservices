#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/env-aliases.sh
source "${ROOT_DIR}/scripts/lib/env-aliases.sh"

: "${K8S_NAMESPACE:?Missing K8S_NAMESPACE}"

kubectl create namespace "${K8S_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

SECRET_NAME="${DOCKER_REGISTRY_SECRET_NAME:-docker-registry-secret}"
REGISTRY="${DOCKER_IMAGE_REGISTRY:-docker.io}"

# shellcheck source=scripts/resolve-ecr-registry.sh
source "${ROOT_DIR}/scripts/resolve-ecr-registry.sh"
REGISTRY="${DOCKER_IMAGE_REGISTRY:-${REGISTRY}}"

if [[ "${REGISTRY}" == *".amazonaws.com"* ]]; then
  : "${AWS_REGION:?Missing AWS_REGION for ECR login}"
  REGISTRY_USERNAME="AWS"
  REGISTRY_PASSWORD="$(aws ecr get-login-password --region "${AWS_REGION}")"
else
  : "${DOCKER_USERNAME:?Missing DOCKER_USERNAME}"
  : "${DOCKER_PASSWORD:?Missing DOCKER_PASSWORD}"
  REGISTRY_USERNAME="${DOCKER_USERNAME}"
  REGISTRY_PASSWORD="${DOCKER_PASSWORD}"
fi

# Build the dockerconfigjson and feed it through stdin so the registry
# password never appears in the process argv (visible via `ps`).
DOCKERCONFIGJSON="$(
  REGISTRY="${REGISTRY}" \
  REGISTRY_USERNAME="${REGISTRY_USERNAME}" \
  REGISTRY_PASSWORD="${REGISTRY_PASSWORD}" \
  python3 - <<'PY'
import base64, json, os

registry = os.environ["REGISTRY"]
username = os.environ["REGISTRY_USERNAME"]
password = os.environ["REGISTRY_PASSWORD"]
auth = base64.b64encode(f"{username}:{password}".encode()).decode()
print(json.dumps({
    "auths": {
        registry: {
            "username": username,
            "password": password,
            "auth": auth,
        }
    }
}))
PY
)"

printf '%s' "${DOCKERCONFIGJSON}" | kubectl create secret generic "${SECRET_NAME}" \
  --type=kubernetes.io/dockerconfigjson \
  --from-file=.dockerconfigjson=/dev/stdin \
  --namespace="${K8S_NAMESPACE}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Docker registry secret ${SECRET_NAME} applied in ${K8S_NAMESPACE}"
