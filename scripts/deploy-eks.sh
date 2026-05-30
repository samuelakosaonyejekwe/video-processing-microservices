#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/env-aliases.sh
source "${ROOT_DIR}/scripts/lib/env-aliases.sh"

: "${AWS_REGION:?Missing AWS_REGION}"
: "${EKS_CLUSTER_NAME:?Missing EKS_CLUSTER_NAME}"
: "${K8S_NAMESPACE:?Missing K8S_NAMESPACE}"

aws eks update-kubeconfig \
  --region "${AWS_REGION}" \
  --name "${EKS_CLUSTER_NAME}"

bash "${ROOT_DIR}/scripts/deploy-helm.sh"

bash "${ROOT_DIR}/scripts/install-cluster-addons.sh"

bash "${ROOT_DIR}/scripts/verify-deployment.sh"
