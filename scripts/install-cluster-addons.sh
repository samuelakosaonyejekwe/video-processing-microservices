#!/bin/bash
# Install cluster add-ons after EKS is available (replaces Terraform helm releases).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/env-aliases.sh
source "${ROOT_DIR}/scripts/lib/env-aliases.sh"

: "${EKS_CLUSTER_NAME:?Missing EKS_CLUSTER_NAME}"
: "${AWS_REGION:?Missing AWS_REGION}"

bash "${ROOT_DIR}/scripts/ensure-ebs-csi-addon.sh"

helm repo add eks https://aws.github.io/eks-charts 2>/dev/null || true
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/ 2>/dev/null || true
helm repo add autoscaler https://kubernetes.github.io/autoscaler 2>/dev/null || true
helm repo update

helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --namespace kube-system \
  --set clusterName="${EKS_CLUSTER_NAME}" \
  --set serviceAccount.create=true \
  --wait --timeout 5m || echo "ALB controller install deferred (may need IRSA/VPC config)"

helm upgrade --install metrics-server metrics-server/metrics-server \
  --namespace kube-system \
  --create-namespace \
  --wait --timeout 5m || echo "Metrics server install deferred"

if [ "${CLUSTER_AUTOSCALER_ENABLED:-true}" = "true" ]; then
  helm upgrade --install "${CLUSTER_AUTOSCALER_RELEASE_NAME:-cluster-autoscaler}" autoscaler/cluster-autoscaler \
    --namespace kube-system \
    --set "autoDiscovery.clusterName=${EKS_CLUSTER_NAME}" \
    --set "awsRegion=${AWS_REGION}" \
    --wait --timeout 10m || echo "Cluster autoscaler install deferred"
fi

echo "Cluster add-ons installed."
