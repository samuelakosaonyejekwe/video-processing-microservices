#!/bin/bash
# start-platform.sh — Restore the video processing platform from low-cost mode.
#
# Handles both soft-stop (nodes=0, Jenkins stopped) and full-destroy recovery.
# Automatically detects what exists and does only what is needed.
#
# Usage:
#   bash scripts/start-platform.sh
#
# Required env vars:
#   AWS_REGION, EKS_CLUSTER_NAME, PROJECT_NAME, APP_ENV
#   TF_STATE_BUCKET, TF_LOCK_TABLE (if EKS or Jenkins needs Terraform recreation)
#   All deployment vars (same as deploy-eks-services.yml)
#
# The script will:
#   1. Detect current infrastructure state
#   2. Recreate missing infrastructure via Terraform (EKS, Jenkins, NAT)
#   3. Configure kubectl
#   4. Scale EKS nodes to desired size
#   5. Start Jenkins EC2
#   6. Install cluster addons (ALB controller, CoreDNS, KEDA, etc.)
#   7. Deploy all services
#   8. Verify cluster health and ingress
#   9. Verify the application is reachable

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

# ---------------------------------------------------------------------------
# Source environment
# ---------------------------------------------------------------------------
# shellcheck source=scripts/lib/env-aliases.sh
source "${ROOT_DIR}/scripts/lib/env-aliases.sh"
if [ -f "${ROOT_DIR}/.env" ]; then
  set +u; set -a
  # shellcheck disable=SC1091
  source "${ROOT_DIR}/.env"
  set +a; set -u
  source "${ROOT_DIR}/scripts/lib/env-aliases.sh"
fi

: "${AWS_REGION:?Missing AWS_REGION}"
: "${EKS_CLUSTER_NAME:?Missing EKS_CLUSTER_NAME}"
: "${PROJECT_NAME:?Missing PROJECT_NAME}"
: "${APP_ENV:?Missing APP_ENV}"
: "${K8S_NAMESPACE:?Missing K8S_NAMESPACE}"

JENKINS_NAME="${PROJECT_NAME}-${APP_ENV}-jenkins"
EKS_DESIRED="${EKS_DESIRED_SIZE:-2}"
EKS_MIN="${EKS_MIN_SIZE:-1}"
EKS_MAX="${EKS_MAX_SIZE:-2}"

log()  { echo "[$(date -u '+%H:%M:%S')] $*"; }
warn() { echo "[$(date -u '+%H:%M:%S')] WARNING: $*" >&2; }
ok()   { echo "[$(date -u '+%H:%M:%S')] ✓ $*"; }

# ---------------------------------------------------------------------------
# Verify AWS credentials
# ---------------------------------------------------------------------------
log "Verifying AWS credentials..."
ACCOUNT_ID="$(aws sts get-caller-identity \
  --region "${AWS_REGION}" \
  --query 'Account' --output text)"
ok "AWS account ${ACCOUNT_ID} verified."

# ---------------------------------------------------------------------------
# STEP 1 — Detect infrastructure state
# ---------------------------------------------------------------------------
log "=== STEP 1: Detecting current infrastructure state ==="

EKS_STATUS="$(aws eks describe-cluster \
  --name "${EKS_CLUSTER_NAME}" \
  --region "${AWS_REGION}" \
  --query 'cluster.status' \
  --output text 2>/dev/null || echo "MISSING")"

JENKINS_ID="$(aws ec2 describe-instances \
  --region "${AWS_REGION}" \
  --filters \
    "Name=tag:Name,Values=${JENKINS_NAME}" \
    "Name=instance-state-name,Values=running,stopped,stopping,pending" \
  --query 'Reservations[0].Instances[0].InstanceId' \
  --output text 2>/dev/null || echo "None")"
[ "${JENKINS_ID}" = "None" ] && JENKINS_ID=""

JENKINS_STATE="MISSING"
if [ -n "${JENKINS_ID}" ]; then
  JENKINS_STATE="$(aws ec2 describe-instances \
    --instance-ids "${JENKINS_ID}" \
    --region "${AWS_REGION}" \
    --query 'Reservations[0].Instances[0].State.Name' \
    --output text 2>/dev/null || echo "unknown")"
fi

# Check for NAT gateway
VPC_ID="$(aws ec2 describe-vpcs \
  --region "${AWS_REGION}" \
  --filters \
    "Name=tag:Name,Values=*${PROJECT_NAME}*${APP_ENV}*" \
    "Name=state,Values=available" \
  --query 'Vpcs[0].VpcId' \
  --output text 2>/dev/null || echo "None")"
[ "${VPC_ID}" = "None" ] && VPC_ID=""

NAT_STATUS="MISSING"
if [ -n "${VPC_ID}" ]; then
  NAT_COUNT="$(aws ec2 describe-nat-gateways \
    --region "${AWS_REGION}" \
    --filter \
      "Name=vpc-id,Values=${VPC_ID}" \
      "Name=state,Values=available,pending" \
    --query 'length(NatGateways)' \
    --output text 2>/dev/null || echo "0")"
  [ "${NAT_COUNT:-0}" -gt 0 ] && NAT_STATUS="OK"
fi

log "EKS cluster '${EKS_CLUSTER_NAME}': ${EKS_STATUS}"
log "Jenkins EC2 '${JENKINS_NAME}': ${JENKINS_STATE} (${JENKINS_ID:-no instance})"
log "NAT Gateway: ${NAT_STATUS}"

NEEDS_TERRAFORM=false
[ "${EKS_STATUS}" = "MISSING" ] && NEEDS_TERRAFORM=true
[ "${JENKINS_STATE}" = "MISSING" ] && NEEDS_TERRAFORM=true
[ "${NAT_STATUS}" = "MISSING" ] && NEEDS_TERRAFORM=true

# CRITICAL: only restore from S3 when the cluster/Jenkins were actually destroyed
# (full mode). On a SOFT start the PVCs/EBS still hold the NEWEST data, so restoring
# an older S3 backup would CLOBBER live data. Capture the pre-recreate state now,
# before the post-terraform refresh overwrites EKS_STATUS.
RESTORE_CLUSTER_DATA=false; [ "${EKS_STATUS}" = "MISSING" ] && RESTORE_CLUSTER_DATA=true
RESTORE_JENKINS_DATA=false; [ "${JENKINS_STATE}" = "MISSING" ] && RESTORE_JENKINS_DATA=true

# ---------------------------------------------------------------------------
# STEP 2 — Terraform recreate missing infrastructure (if needed)
# ---------------------------------------------------------------------------
if [ "${NEEDS_TERRAFORM}" = "true" ]; then
  log "=== STEP 2: Recreating infrastructure via Terraform ==="

  : "${TF_STATE_BUCKET:?Missing TF_STATE_BUCKET (needed for Terraform recreate)}"
  : "${TF_LOCK_TABLE:?Missing TF_LOCK_TABLE (needed for Terraform recreate)}"

  TF_DIR="${ROOT_DIR}/infrastructure/terraform"
  chmod +x "${TF_DIR}/scripts/"*.sh 2>/dev/null || true

  # Generate tfvars from current env
  bash "${TF_DIR}/scripts/generate-terraform-tfvars.sh"

  # Init Terraform
  TF_STATE_BUCKET="${TF_STATE_BUCKET}" \
  TF_LOCK_TABLE="${TF_LOCK_TABLE}" \
    bash "${TF_DIR}/scripts/terraform-init.sh"

  cd "${TF_DIR}"

  # Recreate only what is missing to avoid touching S3/ECR/IAM unnecessarily
  TARGETS=()

  if [ "${EKS_STATUS}" = "MISSING" ] || [ "${NAT_STATUS}" = "MISSING" ]; then
    log "Recreating VPC (NAT Gateway + subnets)..."
    TARGETS+=("-target=module.vpc")
  fi

  if [ "${EKS_STATUS}" = "MISSING" ]; then
    log "Recreating EKS cluster and node group..."
    TARGETS+=("-target=module.eks")
    TARGETS+=("-target=module.iam")
  fi

  if [ "${JENKINS_STATE}" = "MISSING" ]; then
    log "Recreating Jenkins EC2 and EIP..."
    TARGETS+=("-target=module.jenkins")
    TARGETS+=("-target=module.security_groups")
  fi

  # Fresh-recreate var overrides (the live-cluster defaults are the opposite):
  #   create_managed_node_group=true  -> provision the node group (live default false)
  #   adopt_existing_cluster=false    -> don't read a destroyed cluster (live default true)
  #   cluster_encryption_kms_key_arn="" -> create a fresh KMS key for the new cluster
  #                                        (live default pins the existing key)
  RECREATE_VARS=(
    -var=create_managed_node_group=true
    -var=adopt_existing_cluster=false
    -var=cluster_encryption_kms_key_arn=
  )
  if [ ${#TARGETS[@]} -gt 0 ]; then
    terraform apply \
      "${TARGETS[@]}" \
      "${RECREATE_VARS[@]}" \
      -input=false \
      -auto-approve
    log "Terraform apply complete."
  fi

  # Re-apply IRSA roles — OIDC provider ARN changes when EKS is recreated
  if [ "${EKS_STATUS}" = "MISSING" ]; then
    log "Re-applying IRSA roles (OIDC provider ARN has changed)..."
    terraform apply \
      "${RECREATE_VARS[@]}" \
      -input=false \
      -auto-approve
    log "IRSA roles updated."
  fi

  cd "${ROOT_DIR}"

  # Refresh state after apply
  EKS_STATUS="$(aws eks describe-cluster \
    --name "${EKS_CLUSTER_NAME}" \
    --region "${AWS_REGION}" \
    --query 'cluster.status' \
    --output text 2>/dev/null || echo "MISSING")"
  log "EKS cluster status after Terraform: ${EKS_STATUS}"
else
  log "=== STEP 2: Infrastructure exists — skipping Terraform ==="
fi

# ---------------------------------------------------------------------------
# STEP 3 — Wait for EKS cluster to be ACTIVE
# ---------------------------------------------------------------------------
log "=== STEP 3: Waiting for EKS cluster to become ACTIVE ==="
for attempt in $(seq 1 60); do
  STATUS="$(aws eks describe-cluster \
    --name "${EKS_CLUSTER_NAME}" \
    --region "${AWS_REGION}" \
    --query 'cluster.status' \
    --output text 2>/dev/null || echo "UNKNOWN")"
  if [ "${STATUS}" = "ACTIVE" ]; then
    ok "EKS cluster is ACTIVE."
    break
  fi
  log "EKS status: ${STATUS} (attempt ${attempt}/60)..."
  sleep 15
done

# ---------------------------------------------------------------------------
# STEP 4 — Configure kubectl
# ---------------------------------------------------------------------------
log "=== STEP 4: Configuring kubectl ==="
aws eks update-kubeconfig \
  --region "${AWS_REGION}" \
  --name "${EKS_CLUSTER_NAME}"
ok "kubectl configured for cluster '${EKS_CLUSTER_NAME}'."

# ---------------------------------------------------------------------------
# STEP 5 — Scale EKS worker nodes to desired size
# ---------------------------------------------------------------------------
log "=== STEP 5: Scaling EKS worker nodes to ${EKS_DESIRED} ==="

# shellcheck source=scripts/lib/resolve-eks-nodegroup.sh
source "${ROOT_DIR}/scripts/lib/resolve-eks-nodegroup.sh"
# shellcheck source=scripts/lib/tag-eks-worker-instances.sh
source "${ROOT_DIR}/scripts/lib/tag-eks-worker-instances.sh"

NODEGROUP="$(resolve_eks_nodegroup "${EKS_CLUSTER_NAME}" "${AWS_REGION}" "${EKS_NODE_GROUP_NAME:-}")"

CURRENT_DESIRED="$(aws eks describe-nodegroup \
  --cluster-name "${EKS_CLUSTER_NAME}" \
  --nodegroup-name "${NODEGROUP}" \
  --region "${AWS_REGION}" \
  --query 'nodegroup.scalingConfig.desiredSize' \
  --output text 2>/dev/null || echo "0")"

if [ "${CURRENT_DESIRED}" != "${EKS_DESIRED}" ]; then
  log "Scaling '${NODEGROUP}': current=${CURRENT_DESIRED} → desired=${EKS_DESIRED}..."
  aws eks update-nodegroup-config \
    --cluster-name "${EKS_CLUSTER_NAME}" \
    --nodegroup-name "${NODEGROUP}" \
    --region "${AWS_REGION}" \
    --scaling-config "minSize=${EKS_MIN},maxSize=${EKS_MAX},desiredSize=${EKS_DESIRED}"
fi

log "Waiting for node group '${NODEGROUP}' to become active..."
aws eks wait nodegroup-active \
  --cluster-name "${EKS_CLUSTER_NAME}" \
  --nodegroup-name "${NODEGROUP}" \
  --region "${AWS_REGION}"

log "Waiting for ${EKS_DESIRED} nodes to be Ready..."
for _ in $(seq 1 60); do
  READY="$(kubectl get nodes --no-headers 2>/dev/null \
    | awk '$2 == "Ready"' | wc -l | tr -d ' ')"
  if [ "${READY:-0}" -ge "${EKS_DESIRED}" ]; then
    ok "${READY} node(s) Ready."
    kubectl get nodes
    break
  fi
  log "Nodes ready: ${READY:-0}/${EKS_DESIRED}..."
  sleep 10
done

WORKER_TAG="${EKS_WORKER_INSTANCE_NAME:-${PROJECT_NAME}-${APP_ENV}-eks-worker}"
tag_eks_worker_instances "${EKS_CLUSTER_NAME}" "${AWS_REGION}" "${WORKER_TAG}"

# ---------------------------------------------------------------------------
# STEP 5b — AZ guarantee for stateful data
# ---------------------------------------------------------------------------
# Stateful pods (postgres/mongo/rabbitmq/redis) can only schedule onto a node in
# the SAME AZ as their EBS volume. The managed node group's ASG balances across
# AZs, but to GUARANTEE coverage we verify each data-PVC AZ has a Ready node and,
# if not, scale the node group up until it does (bounded). No-op when already covered.
log "=== STEP 5b: Ensuring a Ready node in every AZ that holds a data PVC ==="
DATA_AZS="$(kubectl get pv -o jsonpath='{range .items[?(@.status.phase=="Bound")]}{.spec.nodeAffinity.required.nodeSelectorTerms[0].matchExpressions[0].values[0]}{"\n"}{end}' 2>/dev/null | grep -E '^[a-z]{2}-' | sort -u || true)"
if [ -z "${DATA_AZS}" ]; then
  log "No zoned data PVCs detected — nothing to guarantee."
else
  log "Data PVC AZ(s): $(echo "${DATA_AZS}" | tr '\n' ' ')"
  DESIRED_NOW="${EKS_DESIRED}"; CAP=$((EKS_DESIRED + 3))
  for az in ${DATA_AZS}; do
    tries=0
    while true; do
      N="$(kubectl get nodes -l "topology.kubernetes.io/zone=${az}" --no-headers 2>/dev/null | awk '$2=="Ready"' | wc -l | tr -d ' ')"
      if [ "${N:-0}" -ge 1 ]; then ok "AZ ${az}: ${N} Ready node(s)."; break; fi
      tries=$((tries+1))
      if [ "${tries}" -gt 18 ]; then
        if [ "${DESIRED_NOW}" -lt "${CAP}" ]; then
          DESIRED_NOW=$((DESIRED_NOW + 1))
          NEW_MAX=$(( DESIRED_NOW > EKS_MAX ? DESIRED_NOW : EKS_MAX ))
          warn "No Ready node in ${az}; scaling node group to desired=${DESIRED_NOW} (max=${NEW_MAX}) to force AZ coverage..."
          aws eks update-nodegroup-config --cluster-name "${EKS_CLUSTER_NAME}" \
            --nodegroup-name "${NODEGROUP}" --region "${AWS_REGION}" \
            --scaling-config "minSize=${EKS_MIN},maxSize=${NEW_MAX},desiredSize=${DESIRED_NOW}" >/dev/null 2>&1 || true
          aws eks wait nodegroup-active --cluster-name "${EKS_CLUSTER_NAME}" \
            --nodegroup-name "${NODEGROUP}" --region "${AWS_REGION}" 2>/dev/null || true
          tries=0
        else
          warn "AZ ${az} still has no Ready node at cap (${CAP}). Pods bound to ${az} may stay Pending — check ${az} capacity."
          break
        fi
      fi
      sleep 10
    done
  done
fi

# ---------------------------------------------------------------------------
# STEP 6 — Start Jenkins EC2
# ---------------------------------------------------------------------------
log "=== STEP 6: Starting Jenkins EC2 ==="
bash "${ROOT_DIR}/scripts/start-jenkins.sh"

# ---------------------------------------------------------------------------
# STEP 7 — Install / verify cluster addons
# ---------------------------------------------------------------------------
log "=== STEP 7: Installing cluster addons ==="

chmod +x "${ROOT_DIR}/scripts/"*.sh "${ROOT_DIR}/scripts/lib/"*.sh

# EBS CSI driver (required for PVCs — databases)
bash "${ROOT_DIR}/scripts/ensure-ebs-csi-addon.sh" 2>/dev/null || \
  log "EBS CSI script not found; addon may already be installed."

# Core cluster addons (CNI, CoreDNS, kube-proxy, ALB controller, KEDA)
bash "${ROOT_DIR}/scripts/install-cluster-addons.sh"

# External DNS (auto-updates Route53 when ALB DNS changes)
bash "${ROOT_DIR}/scripts/install-external-dns.sh" 2>/dev/null || \
  warn "ExternalDNS install skipped — Route53 A record may need manual update."

ok "Cluster addons installed."

# ---------------------------------------------------------------------------
# STEP 8 — Deploy all services
# ---------------------------------------------------------------------------
log "=== STEP 8: Deploying all microservices ==="
bash "${ROOT_DIR}/scripts/deploy-services.sh"
ok "Services deployed."

# ---------------------------------------------------------------------------
# STEP 8b/8c/8c2 — Restore data from S3, but ONLY after a full recreate
# ---------------------------------------------------------------------------
# CRITICAL SAFETY GATE: restores run only when the cluster was actually destroyed
# (full mode). On a SOFT start the PVCs still hold the newest data, so restoring
# an older S3 backup would CLOBBER live data. Skip restores entirely in soft mode.
if [ "${RESTORE_CLUSTER_DATA}" != "true" ]; then
  log "=== STEP 8b-8c2: SOFT start — PVC data is intact and authoritative; SKIPPING all S3 restores (no data clobber) ==="
else
  log "=== STEP 8b: Restoring databases from S3 (full recreate) ==="
  if bash "${ROOT_DIR}/scripts/restore-databases.sh"; then
    ok "Database restore step complete."
    kubectl -n "${K8S_NAMESPACE}" rollout restart deployment 2>/dev/null || true
  else
    warn "Database restore FAILED — platform is up but DB data was NOT restored."
    warn "Re-run: DATABASE_BACKUP_BUCKET=... bash scripts/restore-databases.sh"
  fi

  log "=== STEP 8c: Restoring RabbitMQ from S3 ==="
  if bash "${ROOT_DIR}/scripts/restore-rabbitmq.sh"; then
    ok "RabbitMQ restore step complete."
  else
    warn "RabbitMQ restore FAILED — apps recreate queues on connect, but queued messages were NOT restored."
    warn "Re-run: DATABASE_BACKUP_BUCKET=... bash scripts/restore-rabbitmq.sh"
  fi

  log "=== STEP 8c2: Restoring Redis / Grafana dashboards / Prometheus metrics ==="
  bash "${ROOT_DIR}/scripts/restore-redis.sh"      || warn "Redis restore failed (cache will warm naturally)."
  bash "${ROOT_DIR}/scripts/restore-grafana.sh"    || warn "Grafana dashboard restore failed (provisioned dashboards still load from ConfigMap)."
  bash "${ROOT_DIR}/scripts/restore-prometheus.sh" || warn "Prometheus restore failed (metrics start fresh — non-critical)."
fi

# ---------------------------------------------------------------------------
# STEP 8d — Re-point DNS to the freshly provisioned ALB
# ---------------------------------------------------------------------------
# A recreate yields a NEW ALB DNS name. Deterministically point every ingress
# host (apex, api, grafana) at it (idempotent — no-op if already correct).
log "=== STEP 8d: Re-pointing Route53 records to the current ALB ==="
if bash "${ROOT_DIR}/scripts/repoint-dns.sh"; then
  ok "DNS re-pointed to the current ALB."
else
  warn "DNS re-point FAILED — domains may resolve to a stale/absent ALB."
  warn "Re-run: ROUTE53_HOSTED_ZONE_ID=... bash scripts/repoint-dns.sh"
fi

# ---------------------------------------------------------------------------
# STEP 8e — Restore Jenkins home from the latest EBS snapshot
# ---------------------------------------------------------------------------
# Only restore Jenkins after a full recreate. On a soft start Jenkins was merely
# stopped (its EBS data is intact), so restoring an older snapshot would clobber it.
if [ "${RESTORE_JENKINS_DATA}" != "true" ]; then
  log "=== STEP 8e: SOFT start — Jenkins data intact (instance only stopped); SKIPPING snapshot restore ==="
else
  log "=== STEP 8e: Restoring Jenkins home from snapshot (full recreate) ==="
  if bash "${ROOT_DIR}/scripts/restore-jenkins.sh"; then
    ok "Jenkins restore step complete."
  else
    warn "Jenkins restore FAILED — Jenkins is up but may be empty. See restore-jenkins.sh output for manual steps."
  fi
fi

# ---------------------------------------------------------------------------
# STEP 9 — Verify deployments
# ---------------------------------------------------------------------------
log "=== STEP 9: Verifying deployments ==="

log "Waiting for pods to become Ready (up to 5 minutes)..."
for svc in gateway auth converter notification; do
  kubectl rollout status deployment/${svc}-deployment \
    -n "${K8S_NAMESPACE}" \
    --timeout=300s 2>/dev/null || \
  kubectl rollout status deployment/${svc}-service \
    -n "${K8S_NAMESPACE}" \
    --timeout=300s 2>/dev/null || \
  warn "${svc} rollout check failed — check 'kubectl get pods -n ${K8S_NAMESPACE}'"
done

# ---------------------------------------------------------------------------
# STEP 10 — Verify ingress and application
# ---------------------------------------------------------------------------
log "=== STEP 10: Verifying ingress ==="

# Wait for ALB to be provisioned (up to 4 minutes)
for attempt in $(seq 1 24); do
  ALB_DNS="$(kubectl get ingress \
    -n "${K8S_NAMESPACE}" \
    -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")"
  if [ -n "${ALB_DNS}" ]; then
    ok "ALB provisioned: ${ALB_DNS}"
    break
  fi
  log "Waiting for ALB DNS (attempt ${attempt}/24)..."
  sleep 10
done

# Verify Route53 A record points to the new ALB
if [ -n "${ALB_DNS:-}" ]; then
  DOMAIN="${APP_DOMAIN:?ERROR: APP_DOMAIN must be set}"
  HOSTED_ZONE_NAME="${HOSTED_ZONE_NAME:?ERROR: HOSTED_ZONE_NAME must be set}"
  ZONE_ID="$(aws route53 list-hosted-zones \
    --query "HostedZones[?contains(Name, '${HOSTED_ZONE_NAME}')].Id" \
    --output text 2>/dev/null | head -1 | sed 's|/hostedzone/||' || echo "")"

  if [ -n "${ZONE_ID}" ]; then
    CURRENT_ALIAS="$(aws route53 list-resource-record-sets \
      --hosted-zone-id "${ZONE_ID}" \
      --query "ResourceRecordSets[?Name=='${DOMAIN}.'].AliasTarget.DNSName" \
      --output text 2>/dev/null || echo "")"

    if [ "${CURRENT_ALIAS}" != "${ALB_DNS}." ] && [ "${CURRENT_ALIAS}" != "${ALB_DNS}" ]; then
      log "Route53 A record for '${DOMAIN}' points to: ${CURRENT_ALIAS:-none}"
      log "New ALB DNS: ${ALB_DNS}"
      log "ExternalDNS will auto-update this within 1-2 minutes..."

      # If ExternalDNS is not installed, update manually
      if ! kubectl get deployment external-dns -n kube-system >/dev/null 2>&1; then
        warn "ExternalDNS not found. Updating Route53 A record manually..."
        ALB_ZONE_ID="$(aws elbv2 describe-load-balancers \
          --region "${AWS_REGION}" \
          --query "LoadBalancers[?DNSName=='${ALB_DNS}'].CanonicalHostedZoneId" \
          --output text 2>/dev/null || echo "")"

        if [ -n "${ALB_ZONE_ID}" ]; then
          aws route53 change-resource-record-sets \
            --hosted-zone-id "${ZONE_ID}" \
            --change-batch "{
              \"Changes\": [{
                \"Action\": \"UPSERT\",
                \"ResourceRecordSet\": {
                  \"Name\": \"${DOMAIN}\",
                  \"Type\": \"A\",
                  \"AliasTarget\": {
                    \"HostedZoneId\": \"${ALB_ZONE_ID}\",
                    \"DNSName\": \"${ALB_DNS}\",
                    \"EvaluateTargetHealth\": true
                  }
                }
              }]
            }" >/dev/null
          ok "Route53 A record updated: ${DOMAIN} → ${ALB_DNS}"
        fi
      fi
    else
      ok "Route53 A record already correct: ${DOMAIN} → ${ALB_DNS}"
    fi
  fi
fi

# Final health check
log "=== Health check ==="
HEALTH_URL="${API_BASE_URL:-${GATEWAY_BASE_URL:-}}"
if [ -z "${HEALTH_URL}" ] && [ -n "${ALB_DNS:-}" ]; then
  HEALTH_URL="https://${ALB_DNS}"
fi

if [ -n "${HEALTH_URL}" ]; then
  for attempt in $(seq 1 12); do
    if curl -fsS --connect-timeout 10 "${HEALTH_URL%/}/health" >/dev/null 2>&1; then
      ok "Health check passed: ${HEALTH_URL%/}/health"
      break
    fi
    log "Health check attempt ${attempt}/12 (DNS may still be propagating)..."
    sleep 15
  done
else
  warn "GATEWAY_BASE_URL or API_BASE_URL not set. Skipping HTTP health check."
  warn "Once DNS propagates, verify: curl https://${APP_DOMAIN}/health"
fi

log ""
ok "=== PLATFORM STARTUP COMPLETE ==="
log ""
log "Cluster:  ${EKS_CLUSTER_NAME}"
log "Nodes:    ${EKS_DESIRED} worker(s)"
log "ALB:      ${ALB_DNS:-<check kubectl get ingress -n ${K8S_NAMESPACE}>}"
log "Domain:   ${APP_DOMAIN:-<check APP_DOMAIN env var>}"
log ""
log "To scale down again: bash scripts/shutdown-platform.sh [--full]"
