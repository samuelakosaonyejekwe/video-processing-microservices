#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/env-aliases.sh
source "${ROOT_DIR}/scripts/lib/env-aliases.sh"

: "${CLUSTER_AUTOSCALER_RELEASE_NAME:?Missing CLUSTER_AUTOSCALER_RELEASE_NAME}"
: "${EKS_CLUSTER_NAME:?Missing EKS_CLUSTER_NAME}"
: "${AWS_REGION:?Missing AWS_REGION}"

helm repo add autoscaler \
  "${CLUSTER_AUTOSCALER_HELM_REPOSITORY}" 2>/dev/null || true

helm repo update

helm upgrade --install \
  "${CLUSTER_AUTOSCALER_RELEASE_NAME}" \
  autoscaler/"${CLUSTER_AUTOSCALER_HELM_CHART}" \
  --namespace "${KUBE_SYSTEM_NAMESPACE}" \
  --create-namespace \
  --set autoDiscovery.clusterName="${EKS_CLUSTER_NAME}" \
  --set awsRegion="${AWS_REGION}"