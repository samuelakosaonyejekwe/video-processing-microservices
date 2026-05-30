#!/bin/bash
# Ensure aws-ebs-csi-driver addon is ACTIVE with IRSA (root cause of PVC Pending).
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

install_addon() {
  local role_arn="$1"
  local status
  status="$(addon_status)"

  if [ "${status}" = "CREATE_FAILED" ] || [ "${status}" = "DEGRADED" ]; then
    echo "Removing unhealthy EBS CSI addon (status=${status})..."
    aws eks delete-addon \
      --cluster-name "${EKS_CLUSTER_NAME}" \
      --addon-name "${ADDON_NAME}" \
      --region "${AWS_REGION}" >/dev/null || true
    for _ in $(seq 1 30); do
      status="$(addon_status)"
      [ "${status}" = "MISSING" ] && break
      sleep 5
    done
  fi

  status="$(addon_status)"
  if [ "${status}" = "MISSING" ]; then
    echo "Creating EBS CSI addon with IRSA role..."
    aws eks create-addon \
      --cluster-name "${EKS_CLUSTER_NAME}" \
      --addon-name "${ADDON_NAME}" \
      --region "${AWS_REGION}" \
      --service-account-role-arn "${role_arn}" \
      --resolve-conflicts OVERWRITE >/dev/null
  elif [ "${status}" = "ACTIVE" ]; then
    echo "EBS CSI addon already ACTIVE"
  else
    echo "Updating EBS CSI addon to use IRSA role..."
    aws eks update-addon \
      --cluster-name "${EKS_CLUSTER_NAME}" \
      --addon-name "${ADDON_NAME}" \
      --region "${AWS_REGION}" \
      --service-account-role-arn "${role_arn}" \
      --resolve-conflicts OVERWRITE >/dev/null || true
  fi
}

wait_for_active() {
  local status
  for _ in $(seq 1 90); do
    status="$(addon_status)"
    if [ "${status}" = "ACTIVE" ]; then
      echo "EBS CSI addon is ACTIVE"
      return 0
    fi
    if [ "${status}" = "CREATE_FAILED" ] || [ "${status}" = "DEGRADED" ]; then
      aws eks describe-addon \
        --cluster-name "${EKS_CLUSTER_NAME}" \
        --addon-name "${ADDON_NAME}" \
        --region "${AWS_REGION}" \
        --query 'addon.health.issues[0].message' \
        --output text 2>/dev/null || true
      return 1
    fi
    echo "Waiting for EBS CSI addon (status=${status})..."
    sleep 10
  done
  echo "ERROR: EBS CSI addon did not become ACTIVE (status=${status})"
  return 1
}

role_arn="$(ensure_irsa_role)"
install_addon "${role_arn}"
wait_for_active

kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=aws-ebs-csi-driver \
  -n kube-system \
  --timeout=300s || echo "EBS CSI pods not ready yet"

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
