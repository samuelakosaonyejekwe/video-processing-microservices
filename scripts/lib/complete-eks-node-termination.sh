#!/bin/bash
# Complete stuck EKS managed node group termination lifecycle hooks.
set -euo pipefail

complete_eks_node_termination() {
  local cluster="${1:?cluster name required}"
  local nodegroup="${2:?node group name required}"
  local region="${3:?region required}"
  local hook_name="${4:-Terminate-LC-Hook}"

  local asg_name
  asg_name="$(aws eks describe-nodegroup \
    --cluster-name "${cluster}" \
    --nodegroup-name "${nodegroup}" \
    --region "${region}" \
    --query 'nodegroup.resources.autoScalingGroups[0].name' \
    --output text 2>/dev/null || true)"

  if [ -z "${asg_name}" ] || [ "${asg_name}" = "None" ]; then
    echo "No Auto Scaling group found for node group ${nodegroup}; skipping lifecycle completion."
    return 0
  fi

  local instance_ids
  instance_ids="$(aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names "${asg_name}" \
    --region "${region}" \
    --query 'AutoScalingGroups[0].Instances[?LifecycleState==`Terminating:Wait`].InstanceId' \
    --output text 2>/dev/null || true)"

  if [ -z "${instance_ids}" ] || [ "${instance_ids}" = "None" ]; then
    echo "No worker instances waiting on termination lifecycle hooks."
    return 0
  fi

  for instance_id in ${instance_ids}; do
    echo "Completing termination lifecycle hook for ${instance_id}..."
    aws autoscaling complete-lifecycle-action \
      --lifecycle-hook-name "${hook_name}" \
      --auto-scaling-group-name "${asg_name}" \
      --lifecycle-action-result CONTINUE \
      --instance-id "${instance_id}" \
      --region "${region}" >/dev/null
  done

  echo "Waiting for worker instances to terminate..."
  for _ in $(seq 1 30); do
    local remaining
    remaining="$(aws autoscaling describe-auto-scaling-groups \
      --auto-scaling-group-names "${asg_name}" \
      --region "${region}" \
      --query 'length(AutoScalingGroups[0].Instances)' \
      --output text 2>/dev/null || echo 0)"
    if [ "${remaining:-0}" = "0" ]; then
      echo "All worker instances terminated."
      return 0
    fi
    sleep 10
  done

  echo "WARNING: Some worker instances may still be terminating. Check the EC2 console."
}
