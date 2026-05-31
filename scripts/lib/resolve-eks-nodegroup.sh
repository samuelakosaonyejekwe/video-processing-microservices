#!/bin/bash
# Resolve the EKS managed node group name for the configured cluster.
set -euo pipefail

resolve_eks_nodegroup() {
  local cluster="${1:?cluster name required}"
  local region="${2:?region required}"
  local configured="${3:-}"
  local nodegroup=""

  if [ -n "${configured}" ]; then
    if aws eks describe-nodegroup \
      --cluster-name "${cluster}" \
      --nodegroup-name "${configured}" \
      --region "${region}" >/dev/null 2>&1; then
      printf '%s' "${configured}"
      return 0
    fi

    echo "WARNING: Configured node group '${configured}' not found; auto-discovering..." >&2
  fi

  nodegroup="$(aws eks list-nodegroups \
    --cluster-name "${cluster}" \
    --region "${region}" \
    --query 'nodegroups[0]' \
    --output text)"

  if [ -z "${nodegroup}" ] || [ "${nodegroup}" = "None" ]; then
    echo "ERROR: Could not determine EKS node group for cluster ${cluster}" >&2
    return 1
  fi

  printf '%s' "${nodegroup}"
}
