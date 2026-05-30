#!/bin/bash

set -euo pipefail

: "${AWS_REGION:?AWS_REGION is required}"
: "${EKS_CLUSTER_NAME:?EKS_CLUSTER_NAME is required}"

aws eks update-kubeconfig \
  --region "${AWS_REGION}" \
  --name "${EKS_CLUSTER_NAME}"

for attempt in $(seq 1 12); do
  if kubectl cluster-info >/dev/null 2>&1; then
    kubectl cluster-info
    kubectl get nodes
    exit 0
  fi
  echo "Waiting for EKS API access (attempt ${attempt}/12)..."
  sleep 15
done

echo "ERROR: Unable to authenticate to EKS API after update-kubeconfig"
kubectl cluster-info
exit 1
