#!/bin/bash
# Safety guard run BEFORE `terraform apply` on the EKS infrastructure.
#
# The terraform state is intentionally NOT reconciled with the live EKS cluster
# (the live cluster is the 2026-05-30 build; the state describes a failed
# 2026-06-02 rebuild). A full apply would attempt to change the cluster's
# IMMUTABLE secrets-encryption KMS key, which forces FULL CLUSTER REPLACEMENT =
# total production outage. See docs/eks-terraform-state-rebuild-runbook.md.
#
# This guard inspects the saved plan (tfplan) and FAILS the job if the plan
# would destroy/replace the EKS cluster, change its encryption_config, or
# destroy/replace the IRSA OIDC provider. It blocks the catastrophe even on a
# deliberate (but mistaken) manual workflow_dispatch. Benign in-place changes
# (e.g. adding cluster log types) are allowed.
set -euo pipefail

cd infrastructure/terraform

if [ ! -f tfplan ]; then
  echo "ERROR: tfplan not found. Run terraform-plan.sh first."
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required for the apply guard."
  exit 1
fi

terraform show -json tfplan > tfplan.json

# 1) EKS cluster delete or replace (replace = actions contain "delete").
cluster_destroy=$(jq '[.resource_changes[]?
  | select(.type=="aws_eks_cluster")
  | select(.change.actions | index("delete"))] | length' tfplan.json)

# 2) EKS cluster in-place update that changes encryption_config (immutable in AWS
#    -> would error or force replacement at apply time).
enc_change=$(jq '[.resource_changes[]?
  | select(.type=="aws_eks_cluster")
  | select(.change.actions | index("update"))
  | select((.change.before.encryption_config // null) != (.change.after.encryption_config // null))]
  | length' tfplan.json)

# 3) IRSA OIDC provider delete/replace (would break every IRSA role).
oidc_destroy=$(jq '[.resource_changes[]?
  | select(.type=="aws_iam_openid_connect_provider")
  | select(.change.actions | index("delete"))] | length' tfplan.json)

fail=0
if [ "${cluster_destroy:-0}" -gt 0 ]; then
  echo "::error::ABORT: plan would DESTROY/REPLACE the EKS cluster (${cluster_destroy} aws_eks_cluster delete/replace)."
  fail=1
fi
if [ "${enc_change:-0}" -gt 0 ]; then
  echo "::error::ABORT: plan would change the EKS cluster encryption_config (immutable -> forces cluster replacement)."
  fail=1
fi
if [ "${oidc_destroy:-0}" -gt 0 ]; then
  echo "::error::ABORT: plan would DESTROY/REPLACE the IRSA OIDC provider (breaks all IRSA)."
  fail=1
fi

if [ "$fail" -ne 0 ]; then
  echo ""
  echo "The terraform state is not reconciled with the live EKS cluster."
  echo "Refusing to apply. See docs/eks-terraform-state-rebuild-runbook.md."
  echo "For cluster-level changes (k8s version, node type) use AWS-native tools (eksctl/console)."
  rm -f tfplan.json
  exit 1
fi

rm -f tfplan.json
echo "Apply guard passed: no EKS cluster destroy/replace or encryption_config change in plan."
