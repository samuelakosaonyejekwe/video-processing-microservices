#!/bin/bash
# restore-jenkins.sh — Restore JENKINS_HOME from the latest EBS snapshot taken by
# backup-jenkins.sh, into a freshly recreated Jenkins instance.
#
# Mechanism (no data copied through the control machine):
#   1. find newest Component=jenkins-backup snapshot
#   2. create a volume from it in the new instance's AZ, attach as /dev/sdf
#   3. via SSM on the new instance: mount it, stop Jenkins, copy the jenkins-data
#      docker-volume contents in, restart Jenkins, unmount
#   4. detach + delete the temporary volume
#
# The recreated instance has the SSM agent (added in the Jenkins user-data). If
# SSM is not reachable in time this script WARNS (non-fatal) and prints the
# manual restore steps rather than failing the whole start.
#
# Env: PROJECT_NAME, APP_ENV/ENVIRONMENT, AWS_REGION. AWS credentials required.
#      RESTORE_JENKINS=false — skip. SSM_WAIT_SECONDS (default 300).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/env-aliases.sh
source "${ROOT_DIR}/scripts/lib/env-aliases.sh"

log() { echo "[$(date -u '+%H:%M:%S')] restore-jenkins: $*"; }
warn() { echo "[$(date -u '+%H:%M:%S')] restore-jenkins: WARNING: $*" >&2; }

if [ "${RESTORE_JENKINS:-true}" != "true" ]; then
  log "RESTORE_JENKINS=${RESTORE_JENKINS:-} — skipping Jenkins restore."
  exit 0
fi

PROJECT="${PROJECT_NAME:-video-processing}"
ENVIRON="${APP_ENV:-${ENVIRONMENT:-production}}"
REGION="${AWS_REGION:-eu-central-1}"
JENKINS_NAME="${PROJECT}-${ENVIRON}-jenkins"
SSM_WAIT="${SSM_WAIT_SECONDS:-300}"

manual_steps() {
  cat >&2 <<EOF
  ---- MANUAL JENKINS RESTORE (run if automation could not finish) ----
  1. Create a volume from the snapshot and attach to the Jenkins instance:
       aws ec2 create-volume --region ${REGION} --availability-zone <AZ> --snapshot-id ${SNAP:-<snap>}
       aws ec2 attach-volume --region ${REGION} --volume-id <vol> --instance-id ${JID:-<id>} --device /dev/sdf
  2. On the instance:  sudo mkdir -p /mnt/jr && sudo mount /dev/nvme1n1p1 /mnt/jr   # (device per lsblk)
       SRC=\$(sudo find /mnt/jr/var/lib/docker/volumes -maxdepth 1 -name '*jenkins*' | head -1)/_data
       cd /opt/jenkins && docker compose stop jenkins
       DEST=\$(docker volume inspect \$(docker volume ls -q | grep jenkins | head -1) -f '{{.Mountpoint}}')
       sudo rm -rf "\$DEST"/* && sudo cp -a "\$SRC"/. "\$DEST"/
       docker compose up -d && sudo umount /mnt/jr
  3. Detach + delete the temp volume.
  --------------------------------------------------------------------
EOF
}

# --- newest snapshot ---
SNAP="$(aws ec2 describe-snapshots --region "${REGION}" --owner-ids self \
  --filters "Name=tag:Component,Values=jenkins-backup" "Name=tag:Project,Values=${PROJECT}" "Name=status,Values=completed" \
  --query 'sort_by(Snapshots,&StartTime)[-1].SnapshotId' --output text 2>/dev/null || true)"
if [ -z "${SNAP}" ] || [ "${SNAP}" = "None" ]; then
  warn "No Jenkins backup snapshot found — starting with a fresh Jenkins (no restore)."
  exit 0
fi
log "Latest Jenkins backup snapshot: ${SNAP}"

# --- new instance + AZ ---
JID="$(aws ec2 describe-instances --region "${REGION}" \
  --filters "Name=tag:Name,Values=${JENKINS_NAME}" "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].InstanceId' --output text 2>/dev/null | head -1)"
[ -n "${JID}" ] && [ "${JID}" != "None" ] || { warn "No running Jenkins instance to restore into."; manual_steps; exit 0; }
AZ="$(aws ec2 describe-instances --region "${REGION}" --instance-ids "${JID}" \
  --query 'Reservations[].Instances[].Placement.AvailabilityZone | [0]' --output text)"
log "Restoring into instance ${JID} (AZ ${AZ})."

# --- volume from snapshot, attach ---
RVOL="$(aws ec2 create-volume --region "${REGION}" --availability-zone "${AZ}" \
  --snapshot-id "${SNAP}" --volume-type gp3 \
  --tag-specifications "ResourceType=volume,Tags=[{Key=Name,Value=${JENKINS_NAME}-restore-temp},{Key=Project,Value=${PROJECT}},{Key=Component,Value=jenkins-restore-temp}]" \
  --query VolumeId --output text)"
log "Temp restore volume: ${RVOL} — waiting available..."
aws ec2 wait volume-available --region "${REGION}" --volume-ids "${RVOL}"
aws ec2 attach-volume --region "${REGION}" --volume-id "${RVOL}" --instance-id "${JID}" --device /dev/sdf >/dev/null
aws ec2 wait volume-in-use --region "${REGION}" --volume-ids "${RVOL}"
log "Attached ${RVOL} -> ${JID} (/dev/sdf)."

cleanup_volume() {
  log "Detaching + deleting temp volume ${RVOL}..."
  aws ec2 detach-volume --region "${REGION}" --volume-id "${RVOL}" >/dev/null 2>&1 || true
  aws ec2 wait volume-available --region "${REGION}" --volume-ids "${RVOL}" 2>/dev/null || true
  aws ec2 delete-volume --region "${REGION}" --volume-id "${RVOL}" 2>/dev/null || true
}
trap cleanup_volume EXIT

# --- wait for SSM on the new instance ---
log "Waiting up to ${SSM_WAIT}s for SSM agent on ${JID}..."
deadline=$(( $(date +%s) + SSM_WAIT ))
ssm_ready=false
while [ "$(date +%s)" -lt "${deadline}" ]; do
  ping="$(aws ssm describe-instance-information --region "${REGION}" \
    --filters "Key=InstanceIds,Values=${JID}" --query 'InstanceInformationList[].PingStatus | [0]' --output text 2>/dev/null || true)"
  [ "${ping}" = "Online" ] && { ssm_ready=true; break; }
  sleep 10
done
if [ "${ssm_ready}" != "true" ]; then
  warn "SSM not reachable on ${JID}. Temp restore volume ${RVOL} is attached at /dev/sdf."
  trap - EXIT   # leave volume attached so the manual steps can use it
  manual_steps
  exit 0
fi
log "SSM online. Running restore on the instance..."

# --- remote restore via SSM ---
read -r -d '' REMOTE <<'REMOTE_EOF' || true
set -e
# find the just-attached, unmounted data disk (the extra disk with no mountpoint)
DEV=""
for d in $(lsblk -dpno NAME,TYPE | awk '$2=="disk"{print $1}'); do
  # skip the root disk (the one whose partition is mounted at /)
  if lsblk -no MOUNTPOINT "$d" | grep -q '^/$'; then continue; fi
  DEV="$d"
done
[ -n "$DEV" ] || { echo "RESTORE_ERR: no extra disk found"; exit 1; }
PART="$(lsblk -lnpo NAME,TYPE "$DEV" | awk '$2=="part"{print $1}' | head -1)"; PART="${PART:-$DEV}"
mkdir -p /mnt/jr
mount "$PART" /mnt/jr 2>/dev/null || mount -o nouuid "$PART" /mnt/jr
SRC="$(find /mnt/jr/var/lib/docker/volumes -maxdepth 1 -type d -name '*jenkins*' 2>/dev/null | head -1)/_data"
[ -d "$SRC" ] || { echo "RESTORE_ERR: jenkins-data not found on backup ($SRC)"; umount /mnt/jr; exit 1; }
cd /opt/jenkins
docker compose stop jenkins || true
LVOL="$(docker volume ls -q | grep -i jenkins | head -1)"
[ -n "$LVOL" ] || { docker compose up -d; sleep 5; docker compose stop jenkins || true; LVOL="$(docker volume ls -q | grep -i jenkins | head -1)"; }
DEST="$(docker volume inspect "$LVOL" -f '{{.Mountpoint}}')"
[ -d "$DEST" ] || { echo "RESTORE_ERR: local jenkins volume not found"; umount /mnt/jr; exit 1; }
rm -rf "${DEST:?}"/* 2>/dev/null || true
cp -a "$SRC"/. "$DEST"/
docker compose up -d
umount /mnt/jr || true
echo "RESTORE_OK: copied $SRC -> $DEST (vol $LVOL)"
REMOTE_EOF

CMD_ID="$(aws ssm send-command --region "${REGION}" \
  --instance-ids "${JID}" --document-name AWS-RunShellScript \
  --comment "jenkins restore from ${SNAP}" \
  --parameters "commands=$(python3 -c 'import json,sys;print(json.dumps([sys.stdin.read()]))' <<<"${REMOTE}")" \
  --query 'Command.CommandId' --output text)"
log "SSM command ${CMD_ID} dispatched. Waiting..."
aws ssm wait command-executed --region "${REGION}" --command-id "${CMD_ID}" --instance-id "${JID}" 2>/dev/null || true
STATUS="$(aws ssm get-command-invocation --region "${REGION}" --command-id "${CMD_ID}" --instance-id "${JID}" --query Status --output text 2>/dev/null || echo Unknown)"
OUT="$(aws ssm get-command-invocation --region "${REGION}" --command-id "${CMD_ID}" --instance-id "${JID}" --query StandardOutputContent --output text 2>/dev/null || true)"
ERR="$(aws ssm get-command-invocation --region "${REGION}" --command-id "${CMD_ID}" --instance-id "${JID}" --query StandardErrorContent --output text 2>/dev/null || true)"
echo "${OUT}"
if [ "${STATUS}" = "Success" ] && echo "${OUT}" | grep -q RESTORE_OK; then
  log "Jenkins restore SUCCEEDED from ${SNAP}."
else
  warn "Jenkins restore did not confirm success (status=${STATUS}). stderr: ${ERR}"
  manual_steps
fi
