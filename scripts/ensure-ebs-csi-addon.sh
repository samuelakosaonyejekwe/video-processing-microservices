#!/bin/bash
# Ensure aws-ebs-csi-driver is healthy with IRSA via Helm (avoids EKS CreateAddon PassRole).
set -euo pipefail

: "${EKS_CLUSTER_NAME:?Missing EKS_CLUSTER_NAME}"
: "${AWS_REGION:?Missing AWS_REGION}"

ADDON_NAME="aws-ebs-csi-driver"
ROLE_NAME="${EKS_CLUSTER_NAME}-ebs-csi-driver-role"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
OIDC_HOST="$(aws eks describe-cluster \
  --name "${EKS_CLUSTER_NAME}" \
  --region "${AWS_REGION}" \
  --query 'cluster.identity.oidc.issuer' \
  --output text | sed 's|https://||')"

addon_status() {
  aws eks describe-addon \
    --cluster-name "${EKS_CLUSTER_NAME}" \
    --addon-name "${ADDON_NAME}" \
    --region "${AWS_REGION}" \
    --query 'addon.status' \
    --output text 2>/dev/null || echo "MISSING"
}

remove_eks_addon_if_present() {
  local status
  status="$(addon_status)"
  if [ "${status}" = "MISSING" ]; then
    return 0
  fi
  echo "Removing EKS-managed ${ADDON_NAME} addon (status=${status})..."
  aws eks delete-addon \
    --cluster-name "${EKS_CLUSTER_NAME}" \
    --addon-name "${ADDON_NAME}" \
    --region "${AWS_REGION}" >/dev/null || true
  for _ in $(seq 1 30); do
    [ "$(addon_status)" = "MISSING" ] && break
    sleep 5
  done
}

ensure_irsa_role() {
  local trust_policy role_arn
  trust_policy="$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${ACCOUNT_ID}:oidc-provider/${OIDC_HOST}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "${OIDC_HOST}:sub": "system:serviceaccount:kube-system:ebs-csi-controller-sa",
          "${OIDC_HOST}:aud": "sts.amazonaws.com"
        }
      }
    }
  ]
}
EOF
)"

  if ! aws iam get-role --role-name "${ROLE_NAME}" >/dev/null 2>&1; then
    aws iam create-role \
      --role-name "${ROLE_NAME}" \
      --assume-role-policy-document "${trust_policy}" >/dev/null
    aws iam attach-role-policy \
      --role-name "${ROLE_NAME}" \
      --policy-arn "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
    echo "Created IRSA role ${ROLE_NAME}"
  fi

  role_arn="$(aws iam get-role --role-name "${ROLE_NAME}" --query 'Role.Arn' --output text)"
  printf '%s' "${role_arn}"
}

install_via_helm() {
  local role_arn="$1"
  helm repo add aws-ebs-csi-driver https://kubernetes-sigs.github.io/aws-ebs-csi-driver 2>/dev/null || true
  helm repo update
  helm upgrade --install aws-ebs-csi-driver aws-ebs-csi-driver/aws-ebs-csi-driver \
    --namespace kube-system \
    --create-namespace \
    --set controller.serviceAccount.create=true \
    --set controller.serviceAccount.name=ebs-csi-controller-sa \
    --set "controller.serviceAccount.annotations.eks\.amazonaws\.com/role-arn=${role_arn}" \
    --wait --timeout 10m
}

remove_eks_addon_if_present
role_arn="$(ensure_irsa_role)"
install_via_helm "${role_arn}"

kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=aws-ebs-csi-driver \
  -n kube-system \
  --timeout=300s

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

echo "EBS CSI driver ready."
