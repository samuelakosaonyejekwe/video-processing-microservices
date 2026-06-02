#!/bin/bash
# Request ACM certificate for the frontend domain and create Route53 alias to the shared ALB.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/env-aliases.sh
source "${ROOT_DIR}/scripts/lib/env-aliases.sh"

if [ -f "${ROOT_DIR}/.env" ]; then
  set +u
  set -a
  # shellcheck disable=SC1091
  source "${ROOT_DIR}/.env"
  set +a
  set -u
  # shellcheck source=scripts/lib/env-aliases.sh
  source "${ROOT_DIR}/scripts/lib/env-aliases.sh"
fi

aws_region="${AWS_REGION:-eu-central-1}"
frontend_domain="${FRONTEND_DOMAIN_NAME}"
zone_name="${ROUTE53_ZONE_NAME:-${HOSTED_ZONE_NAME}}"

if [ -z "${frontend_domain}" ]; then
  echo "ERROR: FRONTEND_DOMAIN_NAME is empty. Set FRONTEND_URL or FRONTEND_DOMAIN_NAME."
  exit 1
fi

if ! command -v aws >/dev/null 2>&1; then
  echo "ERROR: aws CLI is required."
  exit 1
fi

if ! command -v kubectl >/dev/null 2>&1; then
  echo "ERROR: kubectl is required."
  exit 1
fi

_resolve_zone_id() {
  if [ -n "${ROUTE53_HOSTED_ZONE_ID:-}" ]; then
    printf '%s' "${ROUTE53_HOSTED_ZONE_ID}"
    return 0
  fi
  aws route53 list-hosted-zones-by-name \
    --dns-name "${zone_name}" \
    --query 'HostedZones[0].Id' \
    --output text | sed 's|/hostedzone/||'
}

_upsert_cname_record() {
  local zone_id="$1"
  local name="$2"
  local value="$3"
  local change_batch
  change_batch="$(cat <<EOF
{
  "Comment": "ACM validation for ${frontend_domain}",
  "Changes": [{
    "Action": "UPSERT",
    "ResourceRecordSet": {
      "Name": "${name}",
      "Type": "CNAME",
      "TTL": 300,
      "ResourceRecords": [{"Value": "${value}"}]
    }
  }]
}
EOF
)"
  aws route53 change-resource-record-sets \
    --hosted-zone-id "${zone_id}" \
    --change-batch "${change_batch}" >/dev/null
}

_request_or_reuse_cert() {
  if [ -n "${FRONTEND_ACM_CERTIFICATE_ARN:-}" ] && [[ "${FRONTEND_ACM_CERTIFICATE_ARN}" != *"placeholder"* ]]; then
    echo "Using existing frontend ACM certificate: ${FRONTEND_ACM_CERTIFICATE_ARN}" >&2
    printf '%s' "${FRONTEND_ACM_CERTIFICATE_ARN}"
    return 0
  fi

  local existing_arn
  existing_arn="$(aws acm list-certificates \
    --region "${aws_region}" \
    --certificate-statuses ISSUED PENDING_VALIDATION \
    --query "CertificateSummaryList[?DomainName=='${frontend_domain}'].CertificateArn | [0]" \
    --output text 2>/dev/null || true)"
  if [ -n "${existing_arn}" ] && [ "${existing_arn}" != "None" ]; then
    echo "Found existing ACM certificate for ${frontend_domain}: ${existing_arn}" >&2
    printf '%s' "${existing_arn}"
    return 0
  fi

  echo "Requesting ACM certificate for ${frontend_domain} in ${aws_region}..." >&2
  local cert_arn
  cert_arn="$(aws acm request-certificate \
    --region "${aws_region}" \
    --domain-name "${frontend_domain}" \
    --validation-method DNS \
    --query CertificateArn \
    --output text)"

  local zone_id
  zone_id="$(_resolve_zone_id)"
  if [ -z "${zone_id}" ] || [ "${zone_id}" = "None" ]; then
    echo "ERROR: Could not resolve Route53 hosted zone for ${zone_name}."
    exit 1
  fi

  echo "Waiting for ACM validation record..."
  local validation_name validation_value status attempt=0
  while [ "${attempt}" -lt 30 ]; do
    read -r validation_name validation_value status <<<"$(
      aws acm describe-certificate \
        --region "${aws_region}" \
        --certificate-arn "${cert_arn}" \
        --query 'Certificate.[DomainValidationOptions[0].ResourceRecord.Name,DomainValidationOptions[0].ResourceRecord.Value,DomainValidationOptions[0].ValidationStatus]' \
        --output text
    )"
    if [ -n "${validation_name}" ] && [ "${validation_name}" != "None" ]; then
      break
    fi
    attempt=$((attempt + 1))
    sleep 5
  done

  if [ -z "${validation_name}" ] || [ "${validation_name}" = "None" ]; then
    echo "ERROR: ACM did not return a DNS validation record."
    exit 1
  fi

  echo "Creating ACM validation CNAME: ${validation_name}"
  _upsert_cname_record "${zone_id}" "${validation_name}" "${validation_value}"

  echo "Waiting for certificate to become ISSUED..."
  aws acm wait certificate-validated \
    --region "${aws_region}" \
    --certificate-arn "${cert_arn}"

  printf '%s' "${cert_arn}"
}

_wait_for_alb_hostname() {
  local attempt=0
  local hostname=""
  while [ "${attempt}" -lt 60 ]; do
    hostname="$(kubectl get ingress -n "${K8S_NAMESPACE}" \
      -o jsonpath='{range .items[*]}{.status.loadBalancer.ingress[0].hostname}{"\n"}{end}' 2>/dev/null | awk 'NF {print; exit}')"
    if [ -n "${hostname}" ]; then
      printf '%s' "${hostname}"
      return 0
    fi
    attempt=$((attempt + 1))
    sleep 10
  done
  return 1
}

echo "=== Frontend DNS/TLS setup for ${frontend_domain} ==="

cert_arn="$(_request_or_reuse_cert)"
export FRONTEND_ACM_CERTIFICATE_ARN="${cert_arn}"
echo "Frontend ACM certificate ARN: ${FRONTEND_ACM_CERTIFICATE_ARN}" >&2

echo "Rendering and applying frontend ingress with TLS..."
bash "${ROOT_DIR}/scripts/render-k8s-manifests.sh" "${ROOT_DIR}/.rendered-k8s"
rendered="${ROOT_DIR}/.rendered-k8s/infrastructure/kubernetes/frontend"
kubectl apply -f "${rendered}/deployment.yaml"
kubectl apply -f "${rendered}/service.yaml"
kubectl apply -f "${rendered}/ingress.yaml"

echo "Reconciling shared ALB ingress group..."
gateway_rendered="${ROOT_DIR}/.rendered-k8s/infrastructure/kubernetes/gateway/ingress.yaml"
if [ -f "${gateway_rendered}" ]; then
  kubectl apply -f "${gateway_rendered}"
fi

echo "Waiting for frontend ingress ALB hostname..."
alb_hostname="$(_wait_for_alb_hostname)" || {
  echo "ERROR: Timed out waiting for frontend ingress address."
  kubectl describe ingress "${FRONTEND_INGRESS_NAME:-frontend-ingress}" -n "${K8S_NAMESPACE}" || true
  exit 1
}
echo "ALB hostname: ${alb_hostname}"

alb_zone_id="$(aws elbv2 describe-load-balancers \
  --region "${aws_region}" \
  --query "LoadBalancers[?DNSName=='${alb_hostname}'].CanonicalHostedZoneId | [0]" \
  --output text)"
if [ -z "${alb_zone_id}" ] || [ "${alb_zone_id}" = "None" ]; then
  echo "ERROR: Could not resolve ALB hosted zone ID."
  exit 1
fi

zone_id="$(_resolve_zone_id)"
record_name="${frontend_domain}."
change_batch="$(cat <<EOF
{
  "Comment": "Alias ${frontend_domain} to frontend ALB",
  "Changes": [{
    "Action": "UPSERT",
    "ResourceRecordSet": {
      "Name": "${record_name}",
      "Type": "A",
      "AliasTarget": {
        "HostedZoneId": "${alb_zone_id}",
        "DNSName": "${alb_hostname}.",
        "EvaluateTargetHealth": true
      }
    }
  }]
}
EOF
)"

echo "Creating Route53 alias: ${frontend_domain} -> ${alb_hostname}"
aws route53 change-resource-record-sets \
  --hosted-zone-id "${zone_id}" \
  --change-batch "${change_batch}" >/dev/null

echo "Waiting for frontend rollout..."
kubectl rollout status deployment/frontend-deployment -n "${K8S_NAMESPACE}" --timeout=600s

echo "Frontend DNS/TLS setup complete."
echo "  Domain: https://${frontend_domain}"
echo "  ACM ARN: ${FRONTEND_ACM_CERTIFICATE_ARN}"
echo "  ALB: ${alb_hostname}"
