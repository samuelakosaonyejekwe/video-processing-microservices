#!/bin/bash
# Stop Jenkins by scaling its ASG to zero or stopping the standalone EC2 instance.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/env-aliases.sh
source "${ROOT_DIR}/scripts/lib/env-aliases.sh"

: "${AWS_REGION:?Missing AWS_REGION}"

if [ -n "${JENKINS_ASG_NAME:-}" ]; then
  if aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names "${JENKINS_ASG_NAME}" \
    --region "${AWS_REGION}" \
    --query 'AutoScalingGroups[0].AutoScalingGroupName' \
    --output text 2>/dev/null | grep -Fxq "${JENKINS_ASG_NAME}"; then
    echo "Stopping Jenkins ASG ${JENKINS_ASG_NAME}..."
    aws autoscaling update-auto-scaling-group \
      --auto-scaling-group-name "${JENKINS_ASG_NAME}" \
      --desired-capacity 0 \
      --min-size 0 \
      --region "${AWS_REGION}"
    echo "Jenkins ASG scaled to 0."
    exit 0
  fi

  echo "Jenkins ASG ${JENKINS_ASG_NAME} not found; trying standalone EC2 instance..."
fi

jenkins_name="${JENKINS_INSTANCE_NAME:-${PROJECT_NAME:-video-processing}-${APP_ENV:-production}-jenkins}"
instance_id="$(aws ec2 describe-instances \
  --region "${AWS_REGION}" \
  --filters \
    "Name=tag:Name,Values=${jenkins_name}" \
    "Name=instance-state-name,Values=running,pending,stopping" \
  --query 'Reservations[0].Instances[0].InstanceId' \
  --output text 2>/dev/null || true)"

if [ -z "${instance_id}" ] || [ "${instance_id}" = "None" ]; then
  instance_id="$(aws ec2 describe-instances \
    --region "${AWS_REGION}" \
    --filters \
      "Name=tag:Name,Values=*jenkins*" \
      "Name=instance-state-name,Values=running,pending,stopping" \
    --query 'Reservations[0].Instances[0].InstanceId' \
    --output text 2>/dev/null || true)"
fi

if [ -z "${instance_id}" ] || [ "${instance_id}" = "None" ]; then
  echo "No running Jenkins EC2 instance found. Nothing to stop."
  exit 0
fi

echo "Stopping Jenkins EC2 instance ${instance_id}..."
aws ec2 stop-instances --instance-ids "${instance_id}" --region "${AWS_REGION}" >/dev/null
aws ec2 wait instance-stopped --instance-ids "${instance_id}" --region "${AWS_REGION}"
echo "Jenkins EC2 instance stopped."
