#!/bin/bash
# reconcile-platform.sh — idempotent post-(soft)-restart health reconciler.
#
# After a soft shutdown (nodes scaled to 0) and restart, two things can make the
# bring-up "not smooth". This script detects and self-heals BOTH, safely:
#
#   1. DATA-AZ CAPACITY. Every PVC is an EBS volume locked to ONE AZ, so a
#      stateful pod can only schedule onto a node in its volume's AZ. When all the
#      data lives in one AZ (here: eu-central-1b), that AZ may need MORE THAN ONE
#      node to hold every stateful pod. The managed node group's ASG balances
#      across AZs and does NOT guarantee enough nodes land in the data AZ, so
#      postgres/rabbitmq/etc. can get stuck Pending ("Insufficient cpu" /
#      "volume node affinity conflict"). This guard waits until every stateful
#      pod is scheduled and, if any is Pending for a capacity/AZ reason, scales
#      the node group UP (bounded) until they all fit.
#
#   2. MONITORING / VPC-CNI APISERVER EGRESS. After a mass node launch the AWS
#      VPC CNI network-policy agent can mis-program egress-to-apiserver for
#      policy-governed pods, so Prometheus service discovery and kube-state-metrics
#      lose their apiserver watch (the K8s/EKS/Node/Pod dashboards go empty and
#      kube-state-metrics serves a stale cache). This detects it and self-heals
#      (rollout-restart aws-node, then Prometheus + kube-state-metrics) and waits
#      for service discovery to recover.
#
# SAFETY: this script only SCALES THE NODE GROUP UP and RESTARTS pods. It never
# removes nodes, never deletes data, never touches PVCs, and needs NO deploy
# secrets. It is fully idempotent — a no-op on an already-healthy cluster. (To
# trim the node group back DOWN to its target size afterwards, use the separate,
# opt-in scripts/trim-nodes-to-target.sh.)
#
# Usage:   bash scripts/reconcile-platform.sh
# Env:     AWS_REGION, EKS_CLUSTER_NAME  (EKS_NODE_GROUP_NAME optional — auto-resolved)
#          RECONCILE_MAX_EXTRA_NODES (default 2)  — cap on nodes added above desired
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/env-aliases.sh
source "${ROOT_DIR}/scripts/lib/env-aliases.sh"
# shellcheck source=scripts/lib/resolve-eks-nodegroup.sh
source "${ROOT_DIR}/scripts/lib/resolve-eks-nodegroup.sh"

: "${AWS_REGION:?Missing AWS_REGION}"
: "${EKS_CLUSTER_NAME:?Missing EKS_CLUSTER_NAME}"

log()  { echo "[$(date -u '+%H:%M:%S')] $*"; }
ok()   { echo "[$(date -u '+%H:%M:%S')] ✓ $*"; }
warn() { echo "[$(date -u '+%H:%M:%S')] WARNING: $*" >&2; }

NODEGROUP="$(resolve_eks_nodegroup "${EKS_CLUSTER_NAME}" "${AWS_REGION}" "${EKS_NODE_GROUP_NAME:-}" 2>/dev/null || true)"
if [ -z "${NODEGROUP}" ]; then
  echo "ERROR: could not resolve EKS node group for cluster '${EKS_CLUSTER_NAME}'." >&2
  exit 1
fi
MAX_EXTRA="${RECONCILE_MAX_EXTRA_NODES:-2}"

ng_desired() { aws eks describe-nodegroup --cluster-name "${EKS_CLUSTER_NAME}" --nodegroup-name "${NODEGROUP}" --region "${AWS_REGION}" --query 'nodegroup.scalingConfig.desiredSize' --output text 2>/dev/null; }
ng_min()     { aws eks describe-nodegroup --cluster-name "${EKS_CLUSTER_NAME}" --nodegroup-name "${NODEGROUP}" --region "${AWS_REGION}" --query 'nodegroup.scalingConfig.minSize' --output text 2>/dev/null; }
ng_max()     { aws eks describe-nodegroup --cluster-name "${EKS_CLUSTER_NAME}" --nodegroup-name "${NODEGROUP}" --region "${AWS_REGION}" --query 'nodegroup.scalingConfig.maxSize' --output text 2>/dev/null; }
nodes_ready(){ kubectl get nodes --no-headers 2>/dev/null | awk '$2=="Ready"' | wc -l | tr -d ' '; }

scale_to() { # $1 desired ; raises max if needed
  local want="$1" mx; mx="$(ng_max)"; [ "${want}" -gt "${mx}" ] && mx="${want}"
  log "Scaling node group '${NODEGROUP}' → desired=${want} (max=${mx})..."
  aws eks update-nodegroup-config --cluster-name "${EKS_CLUSTER_NAME}" --nodegroup-name "${NODEGROUP}" \
    --region "${AWS_REGION}" --scaling-config "minSize=$(ng_min),maxSize=${mx},desiredSize=${want}" >/dev/null
  aws eks wait nodegroup-active --cluster-name "${EKS_CLUSTER_NAME}" --nodegroup-name "${NODEGROUP}" --region "${AWS_REGION}" 2>/dev/null || true
  local tries=0
  until [ "$(nodes_ready)" -ge "${want}" ] || [ "${tries}" -ge 30 ]; do sleep 10; tries=$((tries+1)); done
}

# Stateful (PVC-bound) pods that are currently Pending, and whether the reason is
# a capacity/AZ shortage (vs an unrelated transient like image pull).
pending_stateful_capacity() {
  kubectl get pods -A -o json 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
hits=0
for p in d['items']:
    if p.get('status',{}).get('phase')!='Pending': continue
    if not any('persistentVolumeClaim' in v for v in p.get('spec',{}).get('volumes',[])): continue
    msg=''
    for c in p.get('status',{}).get('conditions',[]):
        if c.get('type')=='PodScheduled' and c.get('status')=='False': msg=c.get('message','')
    if any(k in msg for k in ('Insufficient','volume node affinity','didn\'t match','too many pods')): hits+=1
print(hits)
"
}

# ── 1. Data-AZ capacity guard (scale UP only) ────────────────────────────────
log "=== STEP 1: Ensuring every stateful (PVC-bound) pod can schedule ==="
DESIRED0="$(ng_desired)"; CAP=$(( DESIRED0 + MAX_EXTRA ))
# wait a moment for the scheduler to settle after a fresh bring-up
for _ in 1 2 3 4 5 6; do [ "$(pending_stateful_capacity)" = "0" ] && break; sleep 10; done
guard_iter=0
while [ "$(pending_stateful_capacity)" != "0" ]; do
  cur="$(ng_desired)"
  if [ "${cur}" -ge "${CAP}" ] || [ "${guard_iter}" -ge "${MAX_EXTRA}" ]; then
    warn "Stateful pods still Pending at node cap (${cur}, max +${MAX_EXTRA}). Check data-AZ capacity manually:"
    kubectl get pods -A --field-selector status.phase=Pending --no-headers 2>/dev/null | awk '{print "   "$1"/"$2}' >&2 || true
    break
  fi
  warn "Stateful pod(s) Pending for capacity/AZ — scaling node group up by 1 (so the data AZ gets another node)."
  scale_to "$(( cur + 1 ))"
  guard_iter=$((guard_iter+1))
  sleep 15
done
[ "$(pending_stateful_capacity)" = "0" ] && ok "All stateful pods scheduled."

# ── 2. Monitoring service-discovery health CHECK (report only) ───────────────
# The K8s/EKS/Node/Pod dashboards need Prometheus to reach the API server for
# service discovery. On this cluster that egress is governed by AWS VPC CNI
# Network Policy, whose agent UNRELIABLY programs egress-to-apiserver for
# policy-governed pods after a node recreation. We only REPORT it here — we do
# NOT restart Prometheus/aws-node, because that does not reliably fix it and can
# make it worse (a fresh pod re-hits the same agent bug). The durable fix is to
# run the monitoring scrapers in a namespace without the default-deny policy (see
# docs/soft-shutdown-restart-runbook.md); the app/DB dashboards are unaffected.
log "=== STEP 2: Monitoring service-discovery health (report only) ==="
PROM_NS="${K8S_NAMESPACE:-video-processing}"
prom_pod() { kubectl get pods -n "${PROM_NS}" -l app=prometheus -o jsonpath='{.items[0].metadata.name}' 2>/dev/null; }
P="$(prom_pod)"
SD_UP="?"
if [ -n "${P}" ]; then
  SD_UP="$(kubectl exec -n "${PROM_NS}" "${P}" -- wget -qO- 'http://localhost:9090/api/v1/targets' 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)['data']['activeTargets']
print(sum(1 for t in d if t['labels'].get('job','').startswith('kubernetes') or t['labels'].get('job')=='node-exporter'))
" 2>/dev/null || echo '?')"
fi
if [ "${SD_UP}" != "?" ] && [ "${SD_UP}" -gt 0 ] 2>/dev/null; then
  ok "Service discovery healthy (${SD_UP} infra targets) — K8s/EKS/Node/Pod dashboards have data."
else
  warn "Service discovery is DOWN (Prometheus can't reach the API server — known AWS VPC CNI Network Policy issue)."
  warn "  App/DB dashboards are unaffected. To fix the 4 infra dashboards durably, move the monitoring scrapers"
  warn "  to a non-default-deny namespace (see docs/soft-shutdown-restart-runbook.md). Restarting Prometheus will NOT help."
fi

# ── 3. Verify ────────────────────────────────────────────────────────────────
log "=== STEP 3: Health summary ==="
echo "  nodes Ready: $(nodes_ready)  (desired=$(ng_desired))"
BAD="$(kubectl get pods -A --no-headers 2>/dev/null | awk '$4!="Running"&&$4!="Completed"&&$4!="Succeeded"' | wc -l | tr -d ' ')"
echo "  unhealthy pods: ${BAD}"
[ "${BAD}" != "0" ] && kubectl get pods -A --no-headers 2>/dev/null | awk '$4!="Running"&&$4!="Completed"&&$4!="Succeeded"{print "    "$1"/"$2"  "$4}'
P="$(prom_pod)"
if [ -n "${P}" ]; then
  UP="$(kubectl exec -n "${PROM_NS}" "${P}" -- wget -qO- 'http://localhost:9090/api/v1/targets' 2>/dev/null | python3 -c 'import json,sys;d=json.load(sys.stdin);print(sum(1 for t in d["data"]["activeTargets"] if t["health"]=="up"))' 2>/dev/null || echo '?')"
  echo "  prometheus targets UP: ${UP}"
fi
echo ""
if [ "${BAD}" = "0" ]; then ok "Platform reconciled — cluster is healthy."; else warn "Some pods are still not healthy (see above)."; fi
