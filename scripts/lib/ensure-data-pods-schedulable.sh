#!/bin/bash
# ensure-data-pods-schedulable.sh — Guarantee the stateful DB pods are scheduled
# and Ready so they can be dumped before a full teardown.
#
# Full-mode shutdown dumps Postgres/MongoDB via `kubectl exec` BEFORE destroying
# their PVCs (so start-platform can restore the exact pre-shutdown state). That
# only works if the DB pods are running. If the platform was previously
# SOFT-shut-down (worker nodes scaled to 0 — the common "save money first, decide
# on full destroy later" flow), those pods are Pending:
#
#     Error from server (BadRequest): pod postgresql-0 does not have a host assigned
#
# and the dump — and therefore the whole full destroy — aborts to avoid data loss.
#
# This helper brings worker capacity back: it scales the node group up, waits for
# a Ready node in every AZ that holds a data PVC, and waits for the DB pods to be
# Ready, so the dump can run. STEP 1 of shutdown then scales the nodes back to 0
# as usual, so the only cost is a few minutes of transient EC2 time. It is a
# fast no-op when the pods are already Ready (the platform-still-running case).
#
# Usage (sourced):
#   source scripts/lib/ensure-data-pods-schedulable.sh
#   ensure_data_pods_schedulable "${EKS_CLUSTER_NAME}" "${AWS_REGION}" "${DB_NS}"
#
# Expects EKS_DESIRED_SIZE / EKS_MIN_SIZE / EKS_MAX_SIZE in the environment
# (env-aliases.sh provides defaults) and a configured kubectl context.
set -euo pipefail

_EDPS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/resolve-eks-nodegroup.sh
source "${_EDPS_DIR}/resolve-eks-nodegroup.sh"

# Fall back to plain echo if the caller did not define log()/warn().
if ! declare -f log  >/dev/null 2>&1; then log()  { echo "[$(date -u '+%H:%M:%S')] $*"; }; fi
if ! declare -f warn >/dev/null 2>&1; then warn() { echo "[$(date -u '+%H:%M:%S')] WARNING: $*" >&2; }; fi

# Is a pod Ready right now? (Running + Ready condition True)
_edps_pod_ready() {
  local ns="$1" pod="$2" cond
  cond="$(kubectl -n "${ns}" get pod "${pod}" \
    -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)"
  [ "${cond}" = "True" ]
}

ensure_data_pods_schedulable() {
  local cluster="${1:?cluster name required}"
  local region="${2:?region required}"
  local db_ns="${3:-${DATABASE_NAMESPACE:-database}}"
  local pg_pod="${4:-${POSTGRES_RELEASE_NAME:-postgresql}-0}"
  local mongo_pod="${5:-${MONGODB_RELEASE_NAME:-mongodb}-0}"

  local desired="${EKS_DESIRED_SIZE:-2}"
  local min="${EKS_MIN_SIZE:-1}"
  local max="${EKS_MAX_SIZE:-2}"

  # --- Fast path: pods already Ready (platform still running) -> no-op. --------
  if _edps_pod_ready "${db_ns}" "${pg_pod}" && _edps_pod_ready "${db_ns}" "${mongo_pod}"; then
    log "DB pods already Ready — worker capacity present, no scale-up needed."
    return 0
  fi

  log "DB pods are not Ready (likely a prior soft shutdown left worker nodes at 0)."
  log "Bringing worker capacity back so the databases can be dumped before destroy..."

  local nodegroup
  nodegroup="$(resolve_eks_nodegroup "${cluster}" "${region}" "${EKS_NODE_GROUP_NAME:-}")" || {
    warn "Could not resolve EKS node group — cannot guarantee DB pods can schedule."
    return 1
  }

  # --- Scale the node group up if it is below the desired size. ----------------
  local current
  current="$(aws eks describe-nodegroup \
    --cluster-name "${cluster}" --nodegroup-name "${nodegroup}" --region "${region}" \
    --query 'nodegroup.scalingConfig.desiredSize' --output text 2>/dev/null || echo "0")"
  [[ "${current}" =~ ^[0-9]+$ ]] || current=0

  if [ "${current}" -lt "${desired}" ]; then
    local new_max=$(( desired > max ? desired : max ))
    log "Scaling node group '${nodegroup}': desired ${current} -> ${desired} (max=${new_max})..."
    aws eks update-nodegroup-config \
      --cluster-name "${cluster}" --nodegroup-name "${nodegroup}" --region "${region}" \
      --scaling-config "minSize=${min},maxSize=${new_max},desiredSize=${desired}" >/dev/null
  else
    log "Node group '${nodegroup}' desired=${current} already >= ${desired}; waiting for it to settle."
  fi

  log "Waiting for node group '${nodegroup}' to become active..."
  aws eks wait nodegroup-active \
    --cluster-name "${cluster}" --nodegroup-name "${nodegroup}" --region "${region}"

  # Pick up the freshly-scaled nodes in kubectl.
  aws eks update-kubeconfig --region "${region}" --name "${cluster}" >/dev/null 2>&1 || true

  log "Waiting for at least one worker node to be Ready..."
  local i ready
  for i in $(seq 1 60); do
    ready="$(kubectl get nodes --no-headers 2>/dev/null | awk '$2 == "Ready"' | wc -l | tr -d ' ')"
    if [ "${ready:-0}" -ge 1 ]; then
      log "${ready} node(s) Ready."
      break
    fi
    sleep 10
  done

  # --- Guarantee a Ready node in every AZ that holds a data PVC. ---------------
  # Stateful pods can only schedule onto a node in the SAME AZ as their EBS volume.
  local data_azs
  data_azs="$(kubectl get pv -o jsonpath='{range .items[?(@.status.phase=="Bound")]}{.spec.nodeAffinity.required.nodeSelectorTerms[0].matchExpressions[0].values[0]}{"\n"}{end}' 2>/dev/null | grep -E '^[a-z]{2}-' | sort -u || true)"
  if [ -n "${data_azs}" ]; then
    log "Data PVC AZ(s): $(echo "${data_azs}" | tr '\n' ' ')"
    local desired_now="${desired}" cap=$(( desired + 3 )) az tries n new_max2
    for az in ${data_azs}; do
      tries=0
      while true; do
        n="$(kubectl get nodes -l "topology.kubernetes.io/zone=${az}" --no-headers 2>/dev/null | awk '$2=="Ready"' | wc -l | tr -d ' ')"
        if [ "${n:-0}" -ge 1 ]; then log "AZ ${az}: ${n} Ready node(s)."; break; fi
        tries=$(( tries + 1 ))
        if [ "${tries}" -gt 18 ]; then
          if [ "${desired_now}" -lt "${cap}" ]; then
            desired_now=$(( desired_now + 1 ))
            new_max2=$(( desired_now > max ? desired_now : max ))
            warn "No Ready node in ${az}; scaling node group to desired=${desired_now} (max=${new_max2}) to force AZ coverage..."
            aws eks update-nodegroup-config --cluster-name "${cluster}" \
              --nodegroup-name "${nodegroup}" --region "${region}" \
              --scaling-config "minSize=${min},maxSize=${new_max2},desiredSize=${desired_now}" >/dev/null 2>&1 || true
            aws eks wait nodegroup-active --cluster-name "${cluster}" \
              --nodegroup-name "${nodegroup}" --region "${region}" 2>/dev/null || true
            tries=0
          else
            warn "AZ ${az} still has no Ready node at cap (${cap}). DB pod in ${az} may stay Pending."
            break
          fi
        fi
        sleep 10
      done
    done
  fi

  # --- Wait for the DB pods themselves to be Ready. ---------------------------
  # Once a node exists in the pod's AZ the scheduler binds the Pending pod
  # automatically; then give the DB process time to accept connections.
  log "Waiting for DB pods (${pg_pod}, ${mongo_pod}) to become Ready..."
  local rc=0
  kubectl -n "${db_ns}" wait --for=condition=ready "pod/${pg_pod}"    --timeout=300s >/dev/null 2>&1 || rc=1
  kubectl -n "${db_ns}" wait --for=condition=ready "pod/${mongo_pod}" --timeout=300s >/dev/null 2>&1 || rc=1

  if [ "${rc}" -ne 0 ]; then
    warn "DB pods did not all reach Ready within the timeout."
    kubectl -n "${db_ns}" get pods -o wide 2>/dev/null || true
    return 1
  fi

  log "DB pods are Ready — safe to dump."
  return 0
}
