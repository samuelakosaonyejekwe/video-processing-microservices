#!/bin/bash
# Verify the active AWS principal can perform deploy-critical IAM PassRole actions.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/env-aliases.sh
source "${ROOT_DIR}/scripts/lib/env-aliases.sh"

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
POLICY_FILE="${ROOT_DIR}/infrastructure/iam/github-actions-deploy-policy.json"

echo "=== IAM deploy permission check (account ${ACCOUNT_ID}) ==="

if [ ! -f "${POLICY_FILE}" ]; then
  echo "ERROR: Missing policy template at ${POLICY_FILE}"
  exit 1
fi

# The policy is a template: S3 bucket ARNs are ${AWS_S3_*_BUCKET} placeholders so
# no environment-specific bucket name is committed. Render a ready-to-attach copy
# from the current env (sourced from GitHub Variables) before referencing it.
RENDERED_POLICY="$(mktemp)"
trap 'rm -f "${RENDERED_POLICY}"' EXIT
envsubst '${AWS_S3_VIDEO_BUCKET} ${AWS_S3_AUDIO_BUCKET}' < "${POLICY_FILE}" > "${RENDERED_POLICY}"

ROLE_PREFIX="${EKS_CLUSTER_NAME:-video-processing-cluster}"
checks=(
  "iam:PassRole|arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_PREFIX}-alb-controller-role"
  "iam:PassRole|arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_PREFIX}-cluster-autoscaler-role"
  "iam:PassRole|arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_PREFIX}-ebs-csi-driver-role"
)

failures=0
for entry in "${checks[@]}"; do
  action="${entry%%|*}"
  resource="${entry#*|}"
  result="$(aws iam simulate-principal-policy \
    --policy-source-arn "$(aws sts get-caller-identity --query Arn --output text)" \
    --action-names "${action}" \
    --resource-arns "${resource}" \
    --query 'EvaluationResults[0].EvalDecision' \
    --output text 2>/dev/null || echo "unknown")"
  if [ "${result}" = "allowed" ] || [ "${result}" = "implicitAllow" ]; then
    echo "OK   ${action} ${resource}"
  else
    echo "WARN ${action} ${resource} -> ${result}"
    failures=$((failures + 1))
  fi
done

if [ "${failures}" -gt 0 ]; then
  echo ""
  echo "Attach the scoped policy (rendered from ${POLICY_FILE}) to the GitHub Actions IAM user/role:"
  echo "  ${RENDERED_POLICY}"
  exit 1
fi

echo "Deploy IAM permissions look sufficient."
