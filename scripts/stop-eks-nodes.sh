#!/bin/bash
# Scale the EKS managed node group to zero to pause worker EC2 costs.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/env-aliases.sh
source "${ROOT_DIR}/scripts/lib/env-aliases.sh"

: "${AWS_REGION:?Missing AWS_REGION}"
: "${EKS_CLUSTER_NAME:?Missing EKS_CLUSTER_NAME}"

nodegroup="${EKS_NODE_GROUP_NAME:-}"
if [ -z "${nodegroup}" ]; then
  nodegroup="$(aws eks list-nodegroups \
    --cluster-name "${EKS_CLUSTER_NAME}" \
    --region "${AWS_REGION}" \
    --query 'nodegroups[0]' \
    --output text)"
fi

if [ -z "${nodegroup}" ] || [ "${nodegroup}" = "None" ]; then
  echo "ERROR: Could not determine EKS node group for cluster ${EKS_CLUSTER_NAME}" >&2
  exit 1
fi

max_size="${EKS_MAX_SIZE:-2}"

echo "Scaling EKS node group ${nodegroup} in ${EKS_CLUSTER_NAME} to 0..."
aws eks update-nodegroup-config \
  --cluster-name "${EKS_CLUSTER_NAME}" \
  --nodegroup-name "${nodegroup}" \
  --region "${AWS_REGION}" \
  --scaling-config "minSize=0,maxSize=${max_size},desiredSize=0"

echo "Waiting for node group to finish scaling down..."
aws eks wait nodegroup-active \
  --cluster-name "${EKS_CLUSTER_NAME}" \
  --nodegroup-name "${nodegroup}" \
  --region "${AWS_REGION}"

echo "EKS worker nodes scaled to 0. Deploy and validation workflows will fail until nodes are started again."
