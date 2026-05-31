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
  echo "Attach scoped policy from ${POLICY_FILE} to the GitHub Actions IAM user/role."
  exit 1
fi

echo "Deploy IAM permissions look sufficient."
