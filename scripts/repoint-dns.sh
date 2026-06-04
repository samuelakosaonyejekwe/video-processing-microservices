#!/bin/bash
# repoint-dns.sh — Point every ingress host at the current ALB in Route53.
#
# After a full recreate the AWS Load Balancer Controller provisions a NEW ALB with
# a new DNS name. This script reads the live ingresses, finds the ALB they resolve
# to, and UPSERTs an A-ALIAS record for each ingress host (apex, api, grafana, …)
# to that ALB. Deterministic and idempotent — safe to run any time (re-running
# against the same ALB is a no-op).
#
# Env: ROUTE53_HOSTED_ZONE_ID, kubectl context, AWS creds. AWS_REGION optional.
#      DNS_WAIT_SECONDS (default 300) to wait for the ALB to be provisioned.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/env-aliases.sh
source "${ROOT_DIR}/scripts/lib/env-aliases.sh"

log() { echo "[$(date -u '+%H:%M:%S')] repoint-dns: $*"; }
warn() { echo "[$(date -u '+%H:%M:%S')] repoint-dns: WARNING: $*" >&2; }

: "${ROUTE53_HOSTED_ZONE_ID:?Missing ROUTE53_HOSTED_ZONE_ID}"
ZONE_ID="${ROUTE53_HOSTED_ZONE_ID}"
REGION="${AWS_REGION:-eu-central-1}"
WAIT="${DNS_WAIT_SECONDS:-300}"

# --- Wait for the shared ALB to be provisioned and reported on an ingress ---
log "Waiting up to ${WAIT}s for an ALB hostname on the ingresses..."
deadline=$(( $(date +%s) + WAIT )); ALB_DNS=""
while [ "$(date +%s)" -lt "${deadline}" ]; do
  ALB_DNS="$(kubectl get ingress -A -o jsonpath='{range .items[*]}{.status.loadBalancer.ingress[0].hostname}{"\n"}{end}' 2>/dev/null | grep . | head -1 || true)"
  [ -n "${ALB_DNS}" ] && break
  sleep 10
done
[ -n "${ALB_DNS}" ] || { warn "No ALB hostname found on any ingress — is the LB controller running and are ingresses applied?"; exit 1; }
log "ALB: ${ALB_DNS}"

# --- Canonical hosted zone id of that ALB (needed for an ALIAS target) ---
ALB_ZONE="$(aws elbv2 describe-load-balancers --region "${REGION}" \
  --query "LoadBalancers[?DNSName=='${ALB_DNS}'].CanonicalHostedZoneId | [0]" --output text 2>/dev/null)"
[ -n "${ALB_ZONE}" ] && [ "${ALB_ZONE}" != "None" ] || { warn "Could not resolve the ALB canonical hosted zone id."; exit 1; }

# --- Collect every host across all ingresses ---
HOSTS="$(kubectl get ingress -A -o jsonpath='{range .items[*]}{range .spec.rules[*]}{.host}{"\n"}{end}{end}' 2>/dev/null | sort -u | grep . || true)"
[ -n "${HOSTS}" ] || { warn "No ingress hosts found — nothing to repoint."; exit 0; }
log "Hosts to repoint:"; echo "${HOSTS}" | sed 's/^/  - /'

# --- Build one change-batch with an A-ALIAS UPSERT per host ---
CHANGES=""
for h in ${HOSTS}; do
  [ -n "${CHANGES}" ] && CHANGES="${CHANGES},"
  CHANGES="${CHANGES}{\"Action\":\"UPSERT\",\"ResourceRecordSet\":{\"Name\":\"${h}.\",\"Type\":\"A\",\"AliasTarget\":{\"HostedZoneId\":\"${ALB_ZONE}\",\"DNSName\":\"${ALB_DNS}\",\"EvaluateTargetHealth\":true}}}"
done
BATCH="{\"Comment\":\"repoint ingress hosts to current ALB\",\"Changes\":[${CHANGES}]}"
echo "${BATCH}" > /tmp/repoint-dns.json

CID="$(aws route53 change-resource-record-sets --hosted-zone-id "${ZONE_ID}" \
  --change-batch file:///tmp/repoint-dns.json --query 'ChangeInfo.Id' --output text)"
log "Submitted Route53 change ${CID}. Waiting for INSYNC..."
aws route53 wait resource-record-sets-changed --id "${CID}" 2>/dev/null || true
log "DONE — all ingress hosts now alias ${ALB_DNS}."
