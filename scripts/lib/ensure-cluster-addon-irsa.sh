#!/bin/bash
# Create IRSA roles for cluster add-ons (ALB controller, cluster autoscaler).
set -euo pipefail

_ensure_oidc_host() {
  aws eks describe-cluster \
    --name "${EKS_CLUSTER_NAME}" \
    --region "${AWS_REGION}" \
    --query 'cluster.identity.oidc.issuer' \
    --output text | sed 's|https://||'
}

_ensure_irsa_role() {
  local role_name="$1"
  local sa_namespace="$2"
  local sa_name="$3"
  local policy_arns=("${@:4}")

  local account_id oidc_host trust_policy role_arn
  account_id="$(aws sts get-caller-identity --query Account --output text)"
  oidc_host="$(_ensure_oidc_host)"

  trust_policy="$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${account_id}:oidc-provider/${oidc_host}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "${oidc_host}:sub": "system:serviceaccount:${sa_namespace}:${sa_name}",
          "${oidc_host}:aud": "sts.amazonaws.com"
        }
      }
    }
  ]
}
EOF
)"

  if ! aws iam get-role --role-name "${role_name}" >/dev/null 2>&1; then
    aws iam create-role \
      --role-name "${role_name}" \
      --assume-role-policy-document "${trust_policy}" >/dev/null
    echo "Created IRSA role ${role_name}"
  fi

  for policy_arn in "${policy_arns[@]}"; do
    aws iam attach-role-policy \
      --role-name "${role_name}" \
      --policy-arn "${policy_arn}" >/dev/null 2>&1 || true
  done

  role_arn="$(aws iam get-role --role-name "${role_name}" --query 'Role.Arn' --output text)"
  printf '%s' "${role_arn}"
}

ensure_alb_controller_irsa() {
  local role_name="${EKS_CLUSTER_NAME}-aws-load-balancer-controller"
  local policy_name="${EKS_CLUSTER_NAME}-aws-load-balancer-controller"
  local policy_file policy_arn account_id

  account_id="$(aws sts get-caller-identity --query Account --output text)"
  policy_file="$(mktemp)"
  curl -fsSL \
    "https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json" \
    -o "${policy_file}"

  if ! aws iam get-policy --policy-arn "arn:aws:iam::${account_id}:policy/${policy_name}" >/dev/null 2>&1; then
    aws iam create-policy \
      --policy-name "${policy_name}" \
      --policy-document "file://${policy_file}" >/dev/null
  fi
  rm -f "${policy_file}"

  policy_arn="arn:aws:iam::${account_id}:policy/${policy_name}"
  _ensure_irsa_role "${role_name}" "kube-system" "aws-load-balancer-controller" "${policy_arn}"
}

ensure_cluster_autoscaler_irsa() {
  local role_name="${EKS_CLUSTER_NAME}-cluster-autoscaler"
  local policy_name="${EKS_CLUSTER_NAME}-cluster-autoscaler"
  local policy_file policy_arn account_id

  account_id="$(aws sts get-caller-identity --query Account --output text)"
  policy_file="$(mktemp)"
  cat > "${policy_file}" <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "autoscaling:DescribeAutoScalingGroups",
        "autoscaling:DescribeAutoScalingInstances",
        "autoscaling:DescribeLaunchConfigurations",
        "autoscaling:DescribeScalingActivities",
        "autoscaling:DescribeTags",
        "ec2:DescribeImages",
        "ec2:DescribeInstanceTypes",
        "ec2:DescribeLaunchTemplateVersions",
        "ec2:GetInstanceTypesFromInstanceRequirements",
        "eks:DescribeNodegroup"
      ],
      "Resource": ["*"]
    },
    {
      "Effect": "Allow",
      "Action": [
        "autoscaling:SetDesiredCapacity",
        "autoscaling:TerminateInstanceInAutoScalingGroup"
      ],
      "Resource": ["*"],
      "Condition": {
        "StringEquals": {
          "autoscaling:ResourceTag/k8s.io/cluster-autoscaler/enabled": "true",
          "autoscaling:ResourceTag/k8s.io/cluster-autoscaler/${EKS_CLUSTER_NAME}": "owned"
        }
      }
    }
  ]
}
EOF
  sed -i "s/\${EKS_CLUSTER_NAME}/${EKS_CLUSTER_NAME}/g" "${policy_file}"

  if ! aws iam get-policy --policy-arn "arn:aws:iam::${account_id}:policy/${policy_name}" >/dev/null 2>&1; then
    aws iam create-policy \
      --policy-name "${policy_name}" \
      --policy-document "file://${policy_file}" >/dev/null
  fi
  rm -f "${policy_file}"

  policy_arn="arn:aws:iam::${account_id}:policy/${policy_name}"
  _ensure_irsa_role \
    "${role_name}" \
    "kube-system" \
    "cluster-autoscaler-aws-cluster-autoscaler" \
    "${policy_arn}"
}

resolve_vpc_id() {
  if [ -n "${VPC_ID:-}" ] && [ "${VPC_ID}" != "None" ]; then
    printf '%s' "${VPC_ID}"
    return 0
  fi

  local vpc_id
  vpc_id="$(aws ec2 describe-vpcs \
    --region "${AWS_REGION}" \
    --filters "Name=tag:Name,Values=${PROJECT_NAME:-video-processing}-${APP_ENV:-production}-vpc" \
    --query 'Vpcs[0].VpcId' \
    --output text 2>/dev/null || true)"

  if [ -z "${vpc_id}" ] || [ "${vpc_id}" = "None" ]; then
    vpc_id="$(aws eks describe-cluster \
      --name "${EKS_CLUSTER_NAME}" \
      --region "${AWS_REGION}" \
      --query 'cluster.resourcesVpcConfig.vpcId' \
      --output text)"
  fi

  printf '%s' "${vpc_id}"
}
