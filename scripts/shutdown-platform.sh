#!/bin/bash
# shutdown-platform.sh — Low-cost mode for the video processing platform.
#
# Two modes:
#   soft  (default) — scale EKS nodes to 0, stop Jenkins EC2.
#                     EKS control plane + NAT gateway keep running (~$130/month).
#                     Full restart in ~10 minutes with no data loss.
#
#   full            — destroy EKS cluster + Jenkins via Terraform, then destroy
#                     NAT gateway.  Saves ~$290/month.  Restart takes ~25 minutes.
#                     WARNING: EKS PVC data (Postgres, MongoDB) is lost; app data
#                     is recreated fresh from migrations on next startup.
#
# Usage:
#   bash scripts/shutdown-platform.sh            # soft mode
#   bash scripts/shutdown-platform.sh --full     # full destroy mode
#
# Required env vars (all present in GitHub Actions as vars/secrets):
#   AWS_REGION, EKS_CLUSTER_NAME, PROJECT_NAME, APP_ENV
#   TF_STATE_BUCKET, TF_LOCK_TABLE (for full mode)
#   AWS credentials must be configured (aws configure / IAM role / env vars)

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

MODE="soft"
for arg in "$@"; do
  case "${arg}" in
    --full)   MODE="full" ;;
    --yes|-y) export CONFIRM_DESTROY=yes ;;
  esac
done

# ---------------------------------------------------------------------------
# Source environment aliases (normalise variable names)
# ---------------------------------------------------------------------------
# shellcheck source=scripts/lib/env-aliases.sh
source "${ROOT_DIR}/scripts/lib/env-aliases.sh"
# shellcheck source=scripts/lib/confirm-destructive.sh
source "${ROOT_DIR}/scripts/lib/confirm-destructive.sh"
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

JENKINS_NAME="${PROJECT_NAME}-${APP_ENV}-jenkins"

log()  { echo "[$(date -u '+%H:%M:%S')] $*"; }
warn() { echo "[$(date -u '+%H:%M:%S')] WARNING: $*" >&2; }

# ---------------------------------------------------------------------------
# Verify AWS connectivity
# ---------------------------------------------------------------------------
log "Verifying AWS credentials..."
aws sts get-caller-identity --region "${AWS_REGION}" \
  --query 'Account' --output text >/dev/null
log "AWS credentials OK."

# ---------------------------------------------------------------------------
# STEP 0 (full mode only) — Back up databases to S3 BEFORE anything is torn down
# ---------------------------------------------------------------------------
# Full mode destroys the Postgres/MongoDB PVCs. Dump them to S3 first — while the
# nodes and DB pods are still running — so start-platform can restore the exact
# pre-shutdown state. If the dump fails, ABORT the destroy (better to keep paying
# than to silently lose data). Set SKIP_DB_DUMP=true to destroy without a backup.
if [ "${MODE}" = "full" ] && [ "${SKIP_DB_DUMP:-false}" != "true" ]; then
  log "=== STEP 0: Back up databases to S3 before full teardown ==="
  : "${DATABASE_BACKUP_BUCKET:?Missing DATABASE_BACKUP_BUCKET (required to back up DBs before full destroy)}"
  if ! command -v kubectl >/dev/null 2>&1; then
    echo "ERROR: kubectl is required to back up databases before a full destroy." >&2
    exit 1
  fi
  aws eks update-kubeconfig --region "${AWS_REGION}" --name "${EKS_CLUSTER_NAME}" >/dev/null 2>&1 || true

  # The DB pods must be running to be dumped. If the platform was previously
  # soft-shut-down (worker nodes scaled to 0), they are Pending ("does not have a
  # host assigned") and the dump would fail. Bring worker capacity back first;
  # STEP 1 scales the nodes back to 0 afterwards. No-op when DBs are already up.
  # shellcheck source=scripts/lib/ensure-data-pods-schedulable.sh
  source "${ROOT_DIR}/scripts/lib/ensure-data-pods-schedulable.sh"
  if ! ensure_data_pods_schedulable "${EKS_CLUSTER_NAME}" "${AWS_REGION}" "${DATABASE_NAMESPACE:-database}"; then
    echo "ERROR: Could not bring the database pods up for backup — ABORTING full destroy." >&2
    echo "       Investigate worker-node/AZ capacity, or set SKIP_DB_DUMP=true to destroy WITHOUT a backup." >&2
    exit 1
  fi

  if ! bash "${ROOT_DIR}/scripts/dump-databases.sh"; then
    echo "ERROR: Database dump failed — ABORTING full destroy to avoid data loss." >&2
    echo "       Fix the dump, or set SKIP_DB_DUMP=true to destroy WITHOUT a backup." >&2
    exit 1
  fi
  log "Database backup complete."

  # RabbitMQ backup (definitions + durable messages) — the rabbitmq PVC is
  # destroyed with the cluster, so capture it now while the cluster is still up.
  if [ "${SKIP_RABBITMQ_BACKUP:-false}" != "true" ]; then
    log "Backing up RabbitMQ (definitions + messages) to S3..."
    if ! bash "${ROOT_DIR}/scripts/backup-rabbitmq.sh"; then
      echo "ERROR: RabbitMQ backup failed — ABORTING to avoid losing queued messages." >&2
      echo "       Fix it, or set SKIP_RABBITMQ_BACKUP=true to destroy WITHOUT a RabbitMQ backup." >&2
      exit 1
    fi
  fi

  # Grafana hand-built dashboards (PVC destroyed; provisioned ones come from
  # ConfigMap). Non-fatal: dashboards are recoverable config, not core data.
  log "Backing up Grafana dashboards to S3..."
  bash "${ROOT_DIR}/scripts/backup-grafana.sh" || warn "Grafana dashboard backup failed (continuing)."

  # Redis (cache) — PVC destroyed. Non-fatal (cache repopulates), but captured for
  # a truly zero-loss restart.
  log "Backing up Redis to S3..."
  bash "${ROOT_DIR}/scripts/backup-redis.sh" || warn "Redis backup failed (continuing; cache repopulates)."

  # Prometheus metrics history (emptyDir) — best-effort, non-fatal.
  log "Backing up Prometheus metrics to S3..."
  bash "${ROOT_DIR}/scripts/backup-prometheus.sh" || warn "Prometheus backup failed (continuing; metrics non-critical)."

  log "Pre-teardown backups complete — safe to proceed with teardown."
fi

# ---------------------------------------------------------------------------
# STEP 1 — Scale EKS nodes to zero (both modes)
# ---------------------------------------------------------------------------
log "=== STEP 1: Scale EKS worker nodes to 0 ==="

# Resolve node group name
# shellcheck source=scripts/lib/resolve-eks-nodegroup.sh
source "${ROOT_DIR}/scripts/lib/resolve-eks-nodegroup.sh"
NODEGROUP="$(resolve_eks_nodegroup "${EKS_CLUSTER_NAME}" "${AWS_REGION}" "${EKS_NODE_GROUP_NAME:-}" 2>/dev/null || true)"

if [ -z "${NODEGROUP}" ]; then
  warn "Could not find EKS node group for cluster '${EKS_CLUSTER_NAME}'. Skipping node scale-down."
else
  CURRENT_DESIRED="$(aws eks describe-nodegroup \
    --cluster-name "${EKS_CLUSTER_NAME}" \
    --nodegroup-name "${NODEGROUP}" \
    --region "${AWS_REGION}" \
    --query 'nodegroup.scalingConfig.desiredSize' \
    --output text 2>/dev/null || echo "0")"

  if [ "${CURRENT_DESIRED}" != "0" ]; then
    MAX_SIZE="$(aws eks describe-nodegroup \
      --cluster-name "${EKS_CLUSTER_NAME}" \
      --nodegroup-name "${NODEGROUP}" \
      --region "${AWS_REGION}" \
      --query 'nodegroup.scalingConfig.maxSize' \
      --output text 2>/dev/null || echo "2")"

    log "Scaling node group '${NODEGROUP}' from ${CURRENT_DESIRED} → 0..."
    aws eks update-nodegroup-config \
      --cluster-name "${EKS_CLUSTER_NAME}" \
      --nodegroup-name "${NODEGROUP}" \
      --region "${AWS_REGION}" \
      --scaling-config "minSize=0,maxSize=${MAX_SIZE},desiredSize=0"

    log "Waiting for node group to finish scaling down..."
    aws eks wait nodegroup-active \
      --cluster-name "${EKS_CLUSTER_NAME}" \
      --nodegroup-name "${NODEGROUP}" \
      --region "${AWS_REGION}"

    # Drain node objects from Kubernetes API if kubectl is available
    if command -v kubectl >/dev/null 2>&1; then
      aws eks update-kubeconfig \
        --region "${AWS_REGION}" \
        --name "${EKS_CLUSTER_NAME}" >/dev/null 2>&1 || true
      # Remove NotReady nodes (they are gone from AWS side already)
      kubectl get nodes --no-headers 2>/dev/null \
        | awk '{print $1}' \
        | xargs -r kubectl delete node --ignore-not-found 2>/dev/null || true
    fi

    log "EKS nodes scaled to 0. EC2 charges stopped."
  else
    log "EKS nodes already at 0. Nothing to do."
  fi
fi

# ---------------------------------------------------------------------------
# STEP 2 — Stop Jenkins EC2 (both modes)
# ---------------------------------------------------------------------------
log "=== STEP 2: Stop Jenkins EC2 ==="

JENKINS_ID="$(aws ec2 describe-instances \
  --region "${AWS_REGION}" \
  --filters \
    "Name=tag:Name,Values=${JENKINS_NAME}" \
    "Name=instance-state-name,Values=running,pending" \
  --query 'Reservations[0].Instances[0].InstanceId' \
  --output text 2>/dev/null || echo "None")"

if [ -z "${JENKINS_ID}" ] || [ "${JENKINS_ID}" = "None" ]; then
  # Try fallback wildcard search
  JENKINS_ID="$(aws ec2 describe-instances \
    --region "${AWS_REGION}" \
    --filters \
      "Name=tag:Name,Values=*jenkins*" \
      "Name=instance-state-name,Values=running,pending" \
    --query 'Reservations[0].Instances[0].InstanceId' \
    --output text 2>/dev/null || echo "None")"
fi

if [ -n "${JENKINS_ID}" ] && [ "${JENKINS_ID}" != "None" ]; then
  log "Stopping Jenkins EC2 instance ${JENKINS_ID}..."
  aws ec2 stop-instances \
    --instance-ids "${JENKINS_ID}" \
    --region "${AWS_REGION}" >/dev/null
  aws ec2 wait instance-stopped \
    --instance-ids "${JENKINS_ID}" \
    --region "${AWS_REGION}"
  log "Jenkins EC2 stopped. Compute charges stopped; EBS and EIP charges continue at ~\$8/month."
else
  log "No running Jenkins EC2 instance found. Skipping."
fi

# ---------------------------------------------------------------------------
# SOFT MODE — done here
# ---------------------------------------------------------------------------
if [ "${MODE}" = "soft" ]; then
  log ""
  log "=== SOFT SHUTDOWN COMPLETE ==="
  log "Savings:  EKS worker EC2 (~\$60-120/month) + Jenkins EC2 (~\$30/month)"
  log "Remaining cost: EKS control plane (~\$73) + NAT gateway (~\$33) + misc (~\$10) = ~\$116/month"
  log ""
  log "To restart:  bash scripts/start-platform.sh"
  log "For full destroy (saves ~\$290/month):  bash scripts/shutdown-platform.sh --full"
  exit 0
fi

# ---------------------------------------------------------------------------
# FULL MODE — destroy EKS cluster + Jenkins via Terraform, then NAT gateway
# ---------------------------------------------------------------------------
log ""
log "=== FULL SHUTDOWN: Destroying EKS cluster and Jenkins via Terraform ==="
warn "EKS PVC data (Postgres/MongoDB/RabbitMQ) will be LOST."
warn "App databases start empty on next restart (Postgres migrations re-run automatically)."
confirm_destructive "destroy the EKS cluster + Jenkins (EKS PVC data WILL be lost)"

: "${TF_STATE_BUCKET:?Missing TF_STATE_BUCKET (required for full mode)}"
: "${TF_LOCK_TABLE:?Missing TF_LOCK_TABLE (required for full mode)}"

TF_DIR="${ROOT_DIR}/infrastructure/terraform"

# ---------------------------------------------------------------------------
# STEP 2b — Snapshot Jenkins home before it is destroyed
# ---------------------------------------------------------------------------
# Jenkins was stopped in STEP 2, so the EBS snapshot is crash-consistent. This
# is what makes Jenkins lossless across a full destroy (restore-jenkins.sh on
# start). ABORT if it fails — losing CI history/config is not silently acceptable.
if [ "${SKIP_JENKINS_BACKUP:-false}" != "true" ]; then
  log "=== STEP 2b: Snapshot Jenkins home to EBS before teardown ==="
  if ! bash "${ROOT_DIR}/scripts/backup-jenkins.sh"; then
    echo "ERROR: Jenkins backup failed — ABORTING full destroy to avoid losing Jenkins data." >&2
    echo "       Fix it, or set SKIP_JENKINS_BACKUP=true to destroy WITHOUT a Jenkins backup." >&2
    exit 1
  fi
fi

# ---------------------------------------------------------------------------
# STEP 3 — Uninstall Helm releases so ALB + other AWS resources are cleaned up
# ---------------------------------------------------------------------------
log "=== STEP 3: Clean up Kubernetes resources (ALB, KEDA, monitoring) ==="
if command -v kubectl >/dev/null 2>&1 && command -v helm >/dev/null 2>&1; then
  aws eks update-kubeconfig \
    --region "${AWS_REGION}" \
    --name "${EKS_CLUSTER_NAME}" >/dev/null 2>&1 || true

  # Uninstall ingress + load balancer controller so the ALB is properly deleted
  for release_ns in \
    "ingress-nginx:ingress-nginx" \
    "aws-load-balancer-controller:kube-system" \
    "keda:keda" \
    "prometheus:monitoring" \
    "grafana:monitoring" \
    "external-dns:kube-system" \
    "metrics-server:kube-system"; do
    release="${release_ns%%:*}"
    ns="${release_ns##*:}"
    if helm status "${release}" -n "${ns}" >/dev/null 2>&1; then
      log "Uninstalling Helm release '${release}' in namespace '${ns}'..."
      helm uninstall "${release}" -n "${ns}" --wait --timeout 120s 2>/dev/null || true
    fi
  done

  log "Waiting 30s for ALB to be deleted by the controller..."
  sleep 30
else
  warn "kubectl or helm not available. Skipping Kubernetes cleanup."
  warn "ALB may become an orphaned resource. Delete it manually from the AWS console if needed."
fi

# ---------------------------------------------------------------------------
# STEP 3b — Delete ALL EKS node groups (AWS-native)
# ---------------------------------------------------------------------------
# An EKS cluster cannot be deleted while it still has node groups. The running
# node group may NOT be tracked by Terraform (state drift), in which case
# `terraform destroy -target=module.eks` leaves it in place and the cluster
# deletion fails with "Cluster has nodegroups". Delete every node group directly
# first so the Terraform cluster destroy succeeds. (Deleting the node group also
# deletes its EBS-backed PVCs — DB data loss is already expected in full mode;
# AWS Backup snapshots exist for recovery, see docs/database-backups.md.)
log "=== STEP 3b: Delete EKS node groups (handles Terraform-unmanaged node groups) ==="
EXISTING_NGS="$(aws eks list-nodegroups \
  --cluster-name "${EKS_CLUSTER_NAME}" \
  --region "${AWS_REGION}" \
  --query 'nodegroups' --output text 2>/dev/null || echo "")"
if [ -n "${EXISTING_NGS}" ] && [ "${EXISTING_NGS}" != "None" ]; then
  for ng in ${EXISTING_NGS}; do
    log "Deleting node group ${ng}..."
    aws eks delete-nodegroup \
      --cluster-name "${EKS_CLUSTER_NAME}" \
      --nodegroup-name "${ng}" \
      --region "${AWS_REGION}" >/dev/null 2>&1 || true
  done
  for ng in ${EXISTING_NGS}; do
    log "Waiting for node group ${ng} to be deleted (up to ~10 min)..."
    aws eks wait nodegroup-deleted \
      --cluster-name "${EKS_CLUSTER_NAME}" \
      --nodegroup-name "${ng}" \
      --region "${AWS_REGION}" 2>/dev/null || true
  done
  log "All node groups deleted."
else
  log "No node groups found. Nothing to delete."
fi

# ---------------------------------------------------------------------------
# STEP 4 — Terraform init + targeted destroy of EKS and Jenkins
# ---------------------------------------------------------------------------
log "=== STEP 4: Terraform destroy — EKS cluster and Jenkins ==="

chmod +x "${TF_DIR}/scripts/"*.sh 2>/dev/null || true

# Generate tfvars — terraform destroy still needs all required variable values
# (eks_node_instance_type, eks_desired_size, etc. have no defaults in variables.tf)
bash "${TF_DIR}/scripts/generate-terraform-tfvars.sh"

# Init (connects to S3 backend)
TF_STATE_BUCKET="${TF_STATE_BUCKET}" \
TF_LOCK_TABLE="${TF_LOCK_TABLE}" \
  bash "${TF_DIR}/scripts/terraform-init.sh"

cd "${TF_DIR}"

log "Destroying EKS cluster (this takes ~10–15 minutes)..."
terraform destroy \
  -target=module.eks \
  -input=false \
  -auto-approve

log "Destroying Jenkins EC2 + EIP..."
terraform destroy \
  -target=module.jenkins \
  -input=false \
  -auto-approve

cd "${ROOT_DIR}"

# ---------------------------------------------------------------------------
# STEP 5 — Destroy NAT Gateway (biggest remaining cost after EKS)
# ---------------------------------------------------------------------------
log "=== STEP 5: Destroy NAT Gateway ==="

# Find NAT gateways in the VPC
VPC_ID="$(aws ec2 describe-vpcs \
  --region "${AWS_REGION}" \
  --filters \
    "Name=tag:Name,Values=*${PROJECT_NAME}*${APP_ENV}*" \
    "Name=state,Values=available" \
  --query 'Vpcs[0].VpcId' \
  --output text 2>/dev/null || echo "None")"

if [ -n "${VPC_ID}" ] && [ "${VPC_ID}" != "None" ]; then
  NAT_IDS="$(aws ec2 describe-nat-gateways \
    --region "${AWS_REGION}" \
    --filter \
      "Name=vpc-id,Values=${VPC_ID}" \
      "Name=state,Values=available,pending" \
    --query 'NatGateways[*].NatGatewayId' \
    --output text 2>/dev/null || echo "")"

  for nat_id in ${NAT_IDS}; do
    log "Deleting NAT Gateway ${nat_id}..."
    aws ec2 delete-nat-gateway \
      --nat-gateway-id "${nat_id}" \
      --region "${AWS_REGION}" >/dev/null

    log "Waiting for NAT Gateway ${nat_id} to be deleted..."
    aws ec2 wait nat-gateway-deleted \
      --nat-gateway-ids "${nat_id}" \
      --region "${AWS_REGION}" 2>/dev/null || true
    log "NAT Gateway ${nat_id} deleted."
  done

  # Release NAT EIPs (they accrue charges when unassociated)
  NAT_EIPS="$(aws ec2 describe-addresses \
    --region "${AWS_REGION}" \
    --filters \
      "Name=tag:Name,Values=*${PROJECT_NAME}*nat*" \
      "Name=domain,Values=vpc" \
    --query 'Addresses[?AssociationId==null].AllocationId' \
    --output text 2>/dev/null || echo "")"

  for eip_alloc in ${NAT_EIPS}; do
    log "Releasing NAT EIP allocation ${eip_alloc}..."
    aws ec2 release-address \
      --allocation-id "${eip_alloc}" \
      --region "${AWS_REGION}" 2>/dev/null || true
  done
else
  warn "Could not find VPC for project '${PROJECT_NAME}/${APP_ENV}'. Skipping NAT gateway cleanup."
  warn "Check AWS Console for NAT Gateways and delete manually to stop charges."
fi

# ---------------------------------------------------------------------------
# STEP 6 — Remove stale Route53 A record (ALB no longer exists)
# ---------------------------------------------------------------------------
log "=== STEP 6: Remove stale Route53 A record ==="
HOSTED_ZONE_ID="$(aws route53 list-hosted-zones \
  --query "HostedZones[?contains(Name, '${HOSTED_ZONE_NAME}')].Id" \
  --output text 2>/dev/null | head -1 || echo "")"

if [ -n "${HOSTED_ZONE_ID}" ]; then
  ZONE_ID="${HOSTED_ZONE_ID##*/}"
  DOMAIN="${APP_DOMAIN:?ERROR: APP_DOMAIN must be set}"
  EXISTING_RECORD="$(aws route53 list-resource-record-sets \
    --hosted-zone-id "${ZONE_ID}" \
    --query "ResourceRecordSets[?Name=='${DOMAIN}.'].{Name:Name,Type:Type,AliasTarget:AliasTarget}" \
    --output json 2>/dev/null || echo "[]")"

  if echo "${EXISTING_RECORD}" | python3 -c "import sys,json; d=json.load(sys.stdin); exit(0 if len(d)>0 else 1)" 2>/dev/null; then
    log "Stale A record for ${DOMAIN} found — removing (ALB no longer exists)..."
    # ExternalDNS will recreate it when the ALB is restored
    # The record is also managed by Terraform route53 module — Terraform state handles this
    log "Route53 record will be cleaned up by Terraform state on next 'terraform apply'."
  fi
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
log ""
log "=== FULL SHUTDOWN COMPLETE ==="
log ""
log "Destroyed:  EKS cluster, EKS worker nodes, Jenkins EC2/EIP, NAT Gateway/EIP"
log "Preserved:  VPC, subnets, IGW, S3 (state + app), ECR, IAM, Route53 zone, ACM, KMS, DynamoDB"
log ""
log "Remaining cost: ~\$8-12/month (S3 + ECR + Route53 + DynamoDB + KMS)"
log "Monthly savings: ~\$270-290/month"
log ""
log "To restore the full platform:"
log "  bash scripts/start-platform.sh"
log ""
warn "DATABASE NOTE: Postgres and MongoDB PVCs were destroyed with the EKS cluster."
warn "Postgres schema is re-applied automatically by the migration job on next startup."
warn "MongoDB starts empty — no historical conversion records."
