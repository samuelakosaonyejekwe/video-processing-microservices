#!/bin/bash
# Sync missing GitHub repository variables and secrets from local .env.
# Requires: gh CLI authenticated (gh auth login)

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! gh auth status >/dev/null 2>&1; then
  echo "ERROR: gh CLI not authenticated. Run: gh auth login"
  exit 1
fi

if [ -f "${ROOT_DIR}/.env" ]; then
  set +u
  set -a
  # shellcheck disable=SC1091
  source "${ROOT_DIR}/.env"
  set +a
  set -u
fi

# shellcheck source=scripts/lib/env-aliases.sh
source "${ROOT_DIR}/scripts/lib/env-aliases.sh"

REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)"

get_gh_variable() {
  local name="$1"
  if [ -n "${REPO}" ]; then
    gh api "/repos/${REPO}/actions/variables/${name}" --jq '.value' 2>/dev/null || true
    return
  fi
  gh variable get "$name" 2>/dev/null || true
}

gh_var_set() {
  local name="$1"
  local value="$2"
  if [ -z "$value" ]; then
    echo "SKIP var $name (empty)"
    return
  fi
  if gh variable list --json name -q ".[].name" | grep -qx "$name"; then
    echo "OK   var $name (exists)"
  else
    gh variable set "$name" --body "$value"
    echo "SET  var $name"
  fi
}

gh_var_sync() {
  local name="$1"
  local value="$2"
  if [ -z "$value" ]; then
    echo "SKIP var $name (empty)"
    return
  fi
  gh variable set "$name" --body "$value"
  echo "SYNC var $name"
}

gh_secret_set() {
  local name="$1"
  local value="$2"
  if [ -z "$value" ]; then
    echo "SKIP secret $name (empty)"
    return
  fi
  if gh secret list --json name -q ".[].name" | grep -qx "$name"; then
    echo "OK   secret $name (exists)"
  else
    gh secret set "$name" --body "$value"
    echo "SET  secret $name"
  fi
}

# Fill S3 bucket names from GitHub variables when not in local .env
if [ -z "${S3_UPLOAD_BUCKET:-}" ]; then
  S3_UPLOAD_BUCKET="$(gh variable get AWS_S3_VIDEO_BUCKET 2>/dev/null || gh variable get AWS_S3_BUCKET 2>/dev/null || true)"
  export S3_UPLOAD_BUCKET
fi
if [ -z "${S3_AUDIO_BUCKET:-}" ]; then
  S3_AUDIO_BUCKET="$(gh variable get AWS_S3_AUDIO_BUCKET 2>/dev/null || true)"
  export S3_AUDIO_BUCKET
fi

echo "=== GitHub Variables ==="

gh_var_set JWT_ISSUER "${JWT_ISSUER:-video-converter-platform}"
gh_var_set JWT_AUDIENCE "${JWT_AUDIENCE:-video-converter-users}"
if [ -n "${JWT_PRIVATE_KEY:-}" ] || [ -f "${ROOT_DIR}/jwt-private.pem" ]; then
  gh variable set JWT_ALGORITHM --body "RS256"
  echo "SET  var JWT_ALGORITHM=RS256 (RS256 keys detected)"
else
  gh_var_set JWT_ALGORITHM "${JWT_ALGORITHM:-RS256}"
fi
gh_var_set JWT_ACTIVE_KID "${JWT_ACTIVE_KID:-default}"
gh_var_set VIDEO_UPLOAD_QUEUE "${VIDEO_UPLOAD_QUEUE:-}"
gh_var_set NOTIFICATION_QUEUE "${NOTIFICATION_QUEUE:-}"
gh_var_set GATEWAY_EVENTS_QUEUE "${GATEWAY_EVENTS_QUEUE:-}"
S3_UPLOAD_VALUE="$(get_gh_variable AWS_S3_VIDEO_BUCKET)"
if [ -z "${S3_UPLOAD_VALUE}" ]; then
  S3_UPLOAD_VALUE="$(get_gh_variable AWS_S3_BUCKET)"
fi
S3_AUDIO_VALUE="$(get_gh_variable AWS_S3_AUDIO_BUCKET)"
gh_var_sync S3_UPLOAD_BUCKET "${S3_UPLOAD_VALUE}"
gh_var_sync S3_AUDIO_BUCKET "${S3_AUDIO_VALUE}"
gh_var_set VPC_CIDR "${VPC_CIDR:-}"
gh_var_set PUBLIC_SUBNET_CIDRS "${PUBLIC_SUBNET_CIDRS:-}"
gh_var_set AVAILABILITY_ZONES "${AVAILABILITY_ZONES:-}"
gh_var_set ECR_REPOSITORIES "${ECR_REPOSITORIES:-}"
gh_var_set JENKINS_ASG_NAME "${JENKINS_ASG_NAME:-}"
gh_var_set STRESS_TEST_REQUEST_COUNT "${STRESS_TEST_REQUEST_COUNT:-}"
gh_var_set RABBITMQ_TEST_MESSAGE_COUNT "${RABBITMQ_TEST_MESSAGE_COUNT:-}"
gh_var_set CLUSTER_AUTOSCALER_HELM_REPOSITORY "${CLUSTER_AUTOSCALER_HELM_REPOSITORY:-}"
gh_var_set CLUSTER_AUTOSCALER_HELM_CHART "${CLUSTER_AUTOSCALER_HELM_CHART:-}"
gh_var_set CLUSTER_AUTOSCALER_RELEASE_NAME "${CLUSTER_AUTOSCALER_RELEASE_NAME:-}"
gh_var_set CLUSTER_AUTOSCALER_ENABLED "${CLUSTER_AUTOSCALER_ENABLED:-}"

if [ -x "${ROOT_DIR}/scripts/sync-github-registry-vars.sh" ]; then
  bash "${ROOT_DIR}/scripts/sync-github-registry-vars.sh"
fi

echo ""
echo "=== GitHub Secrets ==="

# JWT public key — derive from private key if missing
if [ -z "${JWT_PUBLIC_KEY:-}" ] && [ -f "${ROOT_DIR}/jwt-private.pem" ]; then
  JWT_PUBLIC_KEY="$(openssl rsa -in "${ROOT_DIR}/jwt-private.pem" -pubout 2>/dev/null || true)"
fi

if gh secret list --json name -q ".[].name" | grep -qx "JWT_PUBLIC_KEY"; then
  echo "OK   secret JWT_PUBLIC_KEY (exists)"
else
  gh_secret_set JWT_PUBLIC_KEY "${JWT_PUBLIC_KEY:-}"
fi

echo ""
echo "Done. Review with: gh variable list && gh secret list"
