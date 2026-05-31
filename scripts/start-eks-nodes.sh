#!/bin/bash
# Scale the EKS managed node group back to configured capacity.
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

min_size="${EKS_MIN_SIZE:-1}"
max_size="${EKS_MAX_SIZE:-2}"
desired_size="${EKS_DESIRED_SIZE:-2}"

echo "Scaling EKS node group ${nodegroup} in ${EKS_CLUSTER_NAME} to ${desired_size}..."
aws eks update-nodegroup-config \
  --cluster-name "${EKS_CLUSTER_NAME}" \
  --nodegroup-name "${nodegroup}" \
  --region "${AWS_REGION}" \
  --scaling-config "minSize=${min_size},maxSize=${max_size},desiredSize=${desired_size}"

echo "Waiting for node group to become active..."
aws eks wait nodegroup-active \
  --cluster-name "${EKS_CLUSTER_NAME}" \
  --nodegroup-name "${nodegroup}" \
  --region "${AWS_REGION}"

if command -v kubectl >/dev/null 2>&1; then
  aws eks update-kubeconfig \
    --region "${AWS_REGION}" \
    --name "${EKS_CLUSTER_NAME}" >/dev/null 2>&1 || true

  echo "Waiting for Kubernetes nodes to become Ready..."
  for _ in $(seq 1 60); do
    ready_count="$(kubectl get nodes --no-headers 2>/dev/null | awk '$2 == "Ready" { count++ } END { print count + 0 }')"
    total_count="$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')"
    if [ "${total_count:-0}" -ge "${desired_size}" ] && [ "${ready_count:-0}" -ge "${desired_size}" ]; then
      kubectl get nodes
      echo "EKS worker nodes are Ready. Re-run Deploy EKS Services to restore workloads."
      exit 0
    fi
    sleep 10
  done

  echo "WARNING: Timed out waiting for all nodes to become Ready. Check kubectl get nodes."
  kubectl get nodes 2>/dev/null || true
else
  echo "EKS worker nodes scaled up. Re-run Deploy EKS Services after nodes join the cluster."
fi
