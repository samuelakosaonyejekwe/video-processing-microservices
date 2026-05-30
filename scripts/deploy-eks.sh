#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/env-aliases.sh
source "${ROOT_DIR}/scripts/lib/env-aliases.sh"

: "${AWS_REGION:?Missing AWS_REGION}"
: "${EKS_CLUSTER_NAME:?Missing EKS_CLUSTER_NAME}"
: "${K8S_NAMESPACE:?Missing K8S_NAMESPACE}"

GATEWAY_RELEASE_NAME="${GATEWAY_RELEASE_NAME:-gateway}"

aws eks update-kubeconfig \
  --region "${AWS_REGION}" \
  --name "${EKS_CLUSTER_NAME}"

helm upgrade --install ${GATEWAY_RELEASE_NAME} \
  ./infrastructure/helm/gateway \
  --namespace "${K8S_NAMESPACE}" \
  --create-namespace

kubectl apply -f infrastructure/kubernetes/

bash scripts/verify-deployment.sh