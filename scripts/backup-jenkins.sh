#!/bin/bash
# backup-jenkins.sh — Snapshot the Jenkins EBS root volume so JENKINS_HOME (the
# `jenkins-data` docker volume lives on the root disk) survives a full-mode
# destroy.
#
# Pure AWS API — no SSH/SSM/agent required. Full-mode shutdown stops the Jenkins
# EC2 first (STEP 2), so this snapshot is taken against a STOPPED instance and is
# crash-consistent. Restore with restore-jenkins.sh.
#
#   shutdown (full)  -> backup-jenkins.sh    (snapshot before terraform destroy)
#   start (recreate) -> restore-jenkins.sh   (copy the snapshot back in)
#
# Env: PROJECT_NAME, APP_ENV/ENVIRONMENT, AWS_REGION. AWS credentials required.
#      JENKINS_BACKUP_RETENTION (default 7) — newest N snapshots kept.
#      SKIP_JENKINS_BACKUP=true — skip entirely.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/env-aliases.sh
source "${ROOT_DIR}/scripts/lib/env-aliases.sh"

log() { echo "[$(date -u '+%H:%M:%S')] backup-jenkins: $*"; }

if [ "${SKIP_JENKINS_BACKUP:-false}" = "true" ]; then
  log "SKIP_JENKINS_BACKUP=true — skipping Jenkins snapshot."
  exit 0
fi

PROJECT="${PROJECT_NAME:-video-processing}"
ENVIRON="${APP_ENV:-${ENVIRONMENT:-production}}"
REGION="${AWS_REGION:-eu-central-1}"
RETENTION="${JENKINS_BACKUP_RETENTION:-7}"
JENKINS_NAME="${PROJECT}-${ENVIRON}-jenkins"

# --- Resolve the Jenkins instance (running OR stopped) ---
JID="$(aws ec2 describe-instances --region "${REGION}" \
  --filters "Name=tag:Name,Values=${JENKINS_NAME}" \
            "Name=instance-state-name,Values=running,stopped,stopping" \
  --query 'Reservations[].Instances[].InstanceId' --output text 2>/dev/null | head -1)"
if [ -z "${JID}" ] || [ "${JID}" = "None" ]; then
  JID="$(aws ec2 describe-instances --region "${REGION}" \
    --filters "Name=tag:Name,Values=*jenkins*" \
              "Name=instance-state-name,Values=running,stopped,stopping" \
    --query 'Reservations[].Instances[].InstanceId' --output text 2>/dev/null | head -1)"
fi
if [ -z "${JID}" ] || [ "${JID}" = "None" ]; then
  log "WARNING: no Jenkins instance found — nothing to snapshot. Skipping."
  exit 0
fi
log "Jenkins instance: ${JID}"

# --- Root volume (JENKINS_HOME docker volume lives here) ---
VOL="$(aws ec2 describe-instances --region "${REGION}" --instance-ids "${JID}" \
  --query 'Reservations[].Instances[].BlockDeviceMappings[?DeviceName==`/dev/sda1`].Ebs.VolumeId | [0][0]' \
  --output text 2>/dev/null)"
if [ -z "${VOL}" ] || [ "${VOL}" = "None" ]; then
  VOL="$(aws ec2 describe-instances --region "${REGION}" --instance-ids "${JID}" \
    --query 'Reservations[].Instances[].BlockDeviceMappings[0].Ebs.VolumeId' --output text 2>/dev/null)"
fi
[ -n "${VOL}" ] && [ "${VOL}" != "None" ] || { echo "ERROR: could not resolve Jenkins root volume." >&2; exit 1; }
log "Root volume: ${VOL}"

STATE="$(aws ec2 describe-instances --region "${REGION}" --instance-ids "${JID}" \
  --query 'Reservations[].Instances[].State.Name | [0]' --output text 2>/dev/null)"
[ "${STATE}" = "running" ] && log "NOTE: instance is RUNNING — snapshot is crash-consistent (full shutdown stops it first for a clean snapshot)."

TS="$(date -u +%Y%m%d-%H%M%S)"
log "Creating snapshot of ${VOL}..."
SNAP="$(aws ec2 create-snapshot --region "${REGION}" --volume-id "${VOL}" \
  --description "Jenkins home backup ${TS} (${JENKINS_NAME})" \
  --tag-specifications "ResourceType=snapshot,Tags=[{Key=Name,Value=${JENKINS_NAME}-backup},{Key=Project,Value=${PROJECT}},{Key=Environment,Value=${ENVIRON}},{Key=Component,Value=jenkins-backup},{Key=backup-ts,Value=${TS}}]" \
  --query SnapshotId --output text)"
log "Snapshot ${SNAP} created. Waiting for completion (required before the volume is destroyed)..."
# The FIRST snapshot of a volume copies all used blocks and can take 20-30 min on
# a 50GB disk — longer than `aws ec2 wait` (~10 min). Poll with our own timeout.
WAIT_DEADLINE=$(( $(date +%s) + ${JENKINS_SNAPSHOT_WAIT_SECONDS:-2400} ))
while :; do
  STATE_S="$(aws ec2 describe-snapshots --region "${REGION}" --snapshot-ids "${SNAP}" \
    --query 'Snapshots[0].State' --output text 2>/dev/null || echo error)"
  PROG="$(aws ec2 describe-snapshots --region "${REGION}" --snapshot-ids "${SNAP}" \
    --query 'Snapshots[0].Progress' --output text 2>/dev/null || echo '?')"
  case "${STATE_S}" in
    completed) log "Snapshot ${SNAP} COMPLETED."; break ;;
    error)     echo "ERROR: snapshot ${SNAP} entered 'error' state." >&2; exit 1 ;;
    *)         log "  snapshot ${STATE_S} (${PROG})..." ;;
  esac
  [ "$(date +%s)" -lt "${WAIT_DEADLINE}" ] || { echo "ERROR: snapshot ${SNAP} did not complete in time." >&2; exit 1; }
  sleep 20
done

# --- Retention: keep the newest N jenkins-backup snapshots ---
OLD="$(aws ec2 describe-snapshots --region "${REGION}" --owner-ids self \
  --filters "Name=tag:Component,Values=jenkins-backup" "Name=tag:Project,Values=${PROJECT}" \
  --query 'sort_by(Snapshots,&StartTime)[].SnapshotId' --output text 2>/dev/null || true)"
COUNT="$(echo "${OLD}" | wc -w | tr -d ' ')"
if [ "${COUNT}" -gt "${RETENTION}" ]; then
  REMOVE="$(echo "${OLD}" | tr ' ' '\n' | head -n "$((COUNT - RETENTION))")"
  for s in ${REMOVE}; do
    log "Pruning old snapshot ${s} (retention ${RETENTION})."
    aws ec2 delete-snapshot --region "${REGION}" --snapshot-id "${s}" 2>/dev/null || true
  done
fi

log "DONE. Latest Jenkins backup snapshot: ${SNAP}"
echo "${SNAP}"
