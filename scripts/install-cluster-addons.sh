#!/bin/bash
# Install cluster add-ons after EKS is available (replaces Terraform helm releases).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/env-aliases.sh
source "${ROOT_DIR}/scripts/lib/env-aliases.sh"
# shellcheck source=scripts/lib/ensure-cluster-addon-irsa.sh
source "${ROOT_DIR}/scripts/lib/ensure-cluster-addon-irsa.sh"

: "${EKS_CLUSTER_NAME:?Missing EKS_CLUSTER_NAME}"
: "${AWS_REGION:?Missing AWS_REGION}"

bash "${ROOT_DIR}/scripts/ensure-ebs-csi-addon.sh"

helm repo add eks https://aws.github.io/eks-charts 2>/dev/null || true
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/ 2>/dev/null || true
helm repo add autoscaler https://kubernetes.github.io/autoscaler 2>/dev/null || true
helm repo update

vpc_id="$(resolve_vpc_id)"
alb_role_arn="$(ensure_alb_controller_irsa)"

helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --namespace kube-system \
  --set clusterName="${EKS_CLUSTER_NAME}" \
  --set region="${AWS_REGION}" \
  --set vpcId="${vpc_id}" \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set "serviceAccount.annotations.eks\.amazonaws\.com/role-arn=${alb_role_arn}" \
  --wait --timeout 10m

helm upgrade --install metrics-server metrics-server/metrics-server \
  --namespace kube-system \
  --create-namespace \
  --wait --timeout 5m

if [ "${CLUSTER_AUTOSCALER_ENABLED:-true}" = "true" ]; then
  autoscaler_role_arn="$(ensure_cluster_autoscaler_irsa)"
  autoscaler_values="$(mktemp)"
  cat > "${autoscaler_values}" <<EOF
autoDiscovery:
  clusterName: ${EKS_CLUSTER_NAME}
awsRegion: ${AWS_REGION}
rbac:
  serviceAccount:
    name: cluster-autoscaler-aws-cluster-autoscaler
    annotations:
      eks.amazonaws.com/role-arn: ${autoscaler_role_arn}
extraArgs:
  balance-similar-node-groups: true
  skip-nodes-with-system-pods: false
EOF
  helm upgrade --install "${CLUSTER_AUTOSCALER_RELEASE_NAME:-cluster-autoscaler}" autoscaler/cluster-autoscaler \
    --namespace kube-system \
    -f "${autoscaler_values}" \
    --wait --timeout 10m
  rm -f "${autoscaler_values}"
fi

echo "Cluster add-ons installed."
