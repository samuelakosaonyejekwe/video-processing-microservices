#!/bin/bash
# Install cluster add-ons after EKS is available (replaces Terraform helm releases).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/env-aliases.sh
source "${ROOT_DIR}/scripts/lib/env-aliases.sh"

: "${EKS_CLUSTER_NAME:?Missing EKS_CLUSTER_NAME}"
: "${AWS_REGION:?Missing AWS_REGION}"

helm repo add eks https://aws.github.io/eks-charts 2>/dev/null || true
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/ 2>/dev/null || true
helm repo add autoscaler https://kubernetes.github.io/autoscaler 2>/dev/null || true
helm repo update

echo "Installing EBS CSI driver via EKS addon..."
if aws eks describe-addon \
  --cluster-name "${EKS_CLUSTER_NAME}" \
  --addon-name aws-ebs-csi-driver \
  --region "${AWS_REGION}" >/dev/null 2>&1; then
  aws eks update-addon \
    --cluster-name "${EKS_CLUSTER_NAME}" \
    --addon-name aws-ebs-csi-driver \
    --resolve-conflicts OVERWRITE \
    --region "${AWS_REGION}" >/dev/null || true
else
  aws eks create-addon \
    --cluster-name "${EKS_CLUSTER_NAME}" \
    --addon-name aws-ebs-csi-driver \
    --resolve-conflicts OVERWRITE \
    --region "${AWS_REGION}" >/dev/null || true
fi

status="CREATING"
for _ in $(seq 1 90); do
  status="$(aws eks describe-addon \
    --cluster-name "${EKS_CLUSTER_NAME}" \
    --addon-name aws-ebs-csi-driver \
    --region "${AWS_REGION}" \
    --query 'addon.status' --output text 2>/dev/null || echo "CREATING")"
  if [ "${status}" = "ACTIVE" ]; then
    echo "EBS CSI driver addon is ACTIVE"
    break
  fi
  if [ "${status}" = "CREATE_FAILED" ] || [ "${status}" = "DEGRADED" ]; then
    aws eks describe-addon \
      --cluster-name "${EKS_CLUSTER_NAME}" \
      --addon-name aws-ebs-csi-driver \
      --region "${AWS_REGION}" \
      --query 'addon.statusReason' --output text 2>/dev/null || true
    echo "ERROR: EBS CSI addon failed (status=${status})"
    exit 1
  fi
  echo "Waiting for EBS CSI addon (status=${status})..."
  sleep 10
done

if [ "${status}" != "ACTIVE" ]; then
  echo "ERROR: EBS CSI addon did not become ACTIVE within timeout (status=${status})"
  exit 1
fi

kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=aws-ebs-csi-driver \
  -n kube-system \
  --timeout=300s || echo "EBS CSI pods not ready yet"

# Ensure a default StorageClass exists for PVC binding
if ! kubectl get storageclass 2>/dev/null | grep -q '(default)'; then
  kubectl apply -f - <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp2
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: ebs.csi.aws.com
parameters:
  type: gp2
volumeBindingMode: Immediate
allowVolumeExpansion: true
EOF
fi

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
