#!/bin/bash
# restart-platform-soft.sh — bring the platform back up after a SOFT shutdown,
# smoothly and WITHOUT needing any deploy secrets.
#
# A soft shutdown (scripts/shutdown-platform.sh) only scales the EKS node group to
# 0 and stops the Jenkins EC2. The EKS control plane, every Deployment/StatefulSet,
# all NetworkPolicies and all PVC/EBS data persist. So a soft restart does NOT need
# to re-deploy anything (the workloads reschedule from etcd) — it just:
#   1. scales the node group back up to its desired size,
#   2. starts the Jenkins EC2,
#   3. runs reconcile-platform.sh, which GUARANTEES the data AZ has enough nodes
#      for every stateful pod to schedule (the ASG balances across AZs and does
#      not guarantee enough nodes land in the single AZ that holds the EBS data),
#   4. verifies the public endpoints.
#
# Result: lossless return to the pre-shutdown state. This is the validated,
# low-risk soft-restart path. (Use scripts/start-platform.sh — which DOES redeploy
# and needs all the secrets — only for a FULL recreate after a --full shutdown.)
#
# Usage:  bash scripts/restart-platform-soft.sh
# Env:    AWS_REGION, EKS_CLUSTER_NAME, PROJECT_NAME, APP_ENV
#         EKS_DESIRED_SIZE / EKS_MIN_SIZE / EKS_MAX_SIZE (sizing; default from env)
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/env-aliases.sh
source "${ROOT_DIR}/scripts/lib/env-aliases.sh"
# shellcheck source=scripts/lib/resolve-eks-nodegroup.sh
source "${ROOT_DIR}/scripts/lib/resolve-eks-nodegroup.sh"

: "${AWS_REGION:?Missing AWS_REGION}"
: "${EKS_CLUSTER_NAME:?Missing EKS_CLUSTER_NAME}"
: "${PROJECT_NAME:?Missing PROJECT_NAME}"
: "${APP_ENV:?Missing APP_ENV}"

EKS_DESIRED="${EKS_DESIRED_SIZE:-3}"; EKS_MIN="${EKS_MIN_SIZE:-1}"; EKS_MAX="${EKS_MAX_SIZE:-3}"
JENKINS_NAME="${PROJECT_NAME}-${APP_ENV}-jenkins"
log()  { echo "[$(date -u '+%H:%M:%S')] $*"; }
ok()   { echo "[$(date -u '+%H:%M:%S')] ✓ $*"; }
warn() { echo "[$(date -u '+%H:%M:%S')] WARNING: $*" >&2; }

log "Verifying AWS credentials..."
aws sts get-caller-identity --region "${AWS_REGION}" --query Account --output text >/dev/null
log "AWS OK."

# Safety: this path is for SOFT restart only — refuse if the cluster was destroyed.
EKS_STATUS="$(aws eks describe-cluster --name "${EKS_CLUSTER_NAME}" --region "${AWS_REGION}" --query 'cluster.status' --output text 2>/dev/null || echo MISSING)"
if [ "${EKS_STATUS}" = "MISSING" ]; then
  echo "ERROR: EKS cluster '${EKS_CLUSTER_NAME}' does not exist — this is a FULL recreate, not a soft restart." >&2
  echo "       Use: bash scripts/start-platform.sh  (it recreates infra + redeploys; needs all secrets)." >&2
  exit 1
fi
[ "${EKS_STATUS}" != "ACTIVE" ] && { log "Waiting for EKS to be ACTIVE (currently ${EKS_STATUS})..."; aws eks wait cluster-active --name "${EKS_CLUSTER_NAME}" --region "${AWS_REGION}"; }

aws eks update-kubeconfig --name "${EKS_CLUSTER_NAME}" --region "${AWS_REGION}" >/dev/null 2>&1 || true

# ── STEP 1: scale the node group back up ─────────────────────────────────────
NODEGROUP="$(resolve_eks_nodegroup "${EKS_CLUSTER_NAME}" "${AWS_REGION}" "${EKS_NODE_GROUP_NAME:-}")"
log "=== STEP 1: Scaling node group '${NODEGROUP}' → desired=${EKS_DESIRED} ==="
aws eks update-nodegroup-config --cluster-name "${EKS_CLUSTER_NAME}" --nodegroup-name "${NODEGROUP}" \
  --region "${AWS_REGION}" --scaling-config "minSize=${EKS_MIN},maxSize=${EKS_MAX},desiredSize=${EKS_DESIRED}" >/dev/null
aws eks wait nodegroup-active --cluster-name "${EKS_CLUSTER_NAME}" --nodegroup-name "${NODEGROUP}" --region "${AWS_REGION}"
log "Waiting for ${EKS_DESIRED} node(s) to be Ready..."
tries=0
until [ "$(kubectl get nodes --no-headers 2>/dev/null | awk '$2=="Ready"' | wc -l | tr -d ' ')" -ge "${EKS_DESIRED}" ] || [ "${tries}" -ge 40 ]; do sleep 10; tries=$((tries+1)); done
ok "$(kubectl get nodes --no-headers 2>/dev/null | awk '$2=="Ready"' | wc -l | tr -d ' ') node(s) Ready."

# ── STEP 2: start Jenkins ────────────────────────────────────────────────────
log "=== STEP 2: Starting Jenkins EC2 ==="
JID="$(aws ec2 describe-instances --region "${AWS_REGION}" \
  --filters "Name=tag:Name,Values=${JENKINS_NAME}" "Name=instance-state-name,Values=stopped,stopping,running" \
  --query 'Reservations[].Instances[].InstanceId' --output text 2>/dev/null | head -n1)"
if [ -n "${JID}" ]; then aws ec2 start-instances --instance-ids "${JID}" --region "${AWS_REGION}" >/dev/null 2>&1 && ok "Jenkins ${JID} starting."
else warn "No Jenkins instance found (tag Name=${JENKINS_NAME}); skipping."; fi

# ── STEP 3: reconcile (capacity guard for the data AZ + health) ──────────────
log "=== STEP 3: Reconciling (ensuring stateful pods schedule + health) ==="
bash "${ROOT_DIR}/scripts/reconcile-platform.sh"

# ── STEP 4: verify endpoints ─────────────────────────────────────────────────
log "=== STEP 4: Verifying public endpoints ==="
for host in "${FRONTEND_DOMAIN:-}" "${API_DOMAIN:-}" "${GRAFANA_DOMAIN:-}"; do
  [ -z "${host}" ] && continue
  path="/"; case "${host}" in "${API_DOMAIN:-__}") path="/health";; "${GRAFANA_DOMAIN:-__}") path="/api/health";; esac
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 "https://${host}${path}" 2>/dev/null || echo 000)"
  [ "${code}" = "200" ] && ok "https://${host}${path} → 200" || warn "https://${host}${path} → ${code}"
done

echo ""
ok "Soft restart complete — platform is back up. Data preserved on existing PVCs (no restore needed)."
