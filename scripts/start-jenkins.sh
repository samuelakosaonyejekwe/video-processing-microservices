#!/bin/bash
# Start Jenkins by scaling its ASG to one or starting the standalone EC2 instance.
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
    echo "Starting Jenkins ASG ${JENKINS_ASG_NAME}..."
    aws autoscaling update-auto-scaling-group \
      --auto-scaling-group-name "${JENKINS_ASG_NAME}" \
      --desired-capacity 1 \
      --min-size 1 \
      --max-size 1 \
      --region "${AWS_REGION}"
    echo "Jenkins ASG scaled to 1."
    exit 0
  fi

  echo "Jenkins ASG ${JENKINS_ASG_NAME} not found; trying standalone EC2 instance..."
fi

jenkins_name="${JENKINS_INSTANCE_NAME:-${PROJECT_NAME:-video-processing}-${APP_ENV:-production}-jenkins}"
instance_id="$(aws ec2 describe-instances \
  --region "${AWS_REGION}" \
  --filters \
    "Name=tag:Name,Values=${jenkins_name}" \
    "Name=instance-state-name,Values=stopped,stopping,pending,running" \
  --query 'Reservations[0].Instances[0].InstanceId' \
  --output text 2>/dev/null || true)"

if [ -z "${instance_id}" ] || [ "${instance_id}" = "None" ]; then
  instance_id="$(aws ec2 describe-instances \
    --region "${AWS_REGION}" \
    --filters \
      "Name=tag:Name,Values=*jenkins*" \
      "Name=instance-state-name,Values=stopped,stopping,pending,running" \
    --query 'Reservations[0].Instances[0].InstanceId' \
    --output text 2>/dev/null || true)"
fi

if [ -z "${instance_id}" ] || [ "${instance_id}" = "None" ]; then
  echo "ERROR: No Jenkins EC2 instance found to start." >&2
  exit 1
fi

state="$(aws ec2 describe-instances \
  --instance-ids "${instance_id}" \
  --region "${AWS_REGION}" \
  --query 'Reservations[0].Instances[0].State.Name' \
  --output text)"

if [ "${state}" = "running" ]; then
  echo "Jenkins EC2 instance ${instance_id} is already running."
  exit 0
fi

echo "Starting Jenkins EC2 instance ${instance_id}..."
aws ec2 start-instances --instance-ids "${instance_id}" --region "${AWS_REGION}" >/dev/null
aws ec2 wait instance-running --instance-ids "${instance_id}" --region "${AWS_REGION}"
echo "Jenkins EC2 instance started."
