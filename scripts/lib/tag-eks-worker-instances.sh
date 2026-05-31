#!/bin/bash
# Apply production-standard Name tags to EKS worker EC2 instances.
set -euo pipefail

tag_eks_worker_instances() {
  local cluster="${1:?cluster name required}"
  local region="${2:?region required}"
  local name_tag="${3:?instance name tag required}"

  local instance_ids
  instance_ids="$(aws ec2 describe-instances \
    --region "${region}" \
    --filters \
      "Name=tag:eks:cluster-name,Values=${cluster}" \
      "Name=instance-state-name,Values=running,pending" \
    --query 'Reservations[].Instances[].InstanceId' \
    --output text 2>/dev/null || true)"

  if [ -z "${instance_ids}" ] || [ "${instance_ids}" = "None" ]; then
    echo "No running EKS worker instances found to tag."
    return 0
  fi

  for instance_id in ${instance_ids}; do
    aws ec2 create-tags \
      --resources "${instance_id}" \
      --region "${region}" \
      --tags "Key=Name,Value=${name_tag}" >/dev/null
    echo "Tagged ${instance_id} as ${name_tag}"
  done
}
