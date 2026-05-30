#!/bin/bash
# Canonical environment variable aliases.
# Source this before deploy, terraform, or local docker-compose runs so
# GitHub variable names map to names expected by application code and K8s.

set -euo pipefail

_ENV_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${ROOT_DIR:-$(cd "${_ENV_LIB_DIR}/../.." && pwd)}"

_first_nonempty() {
  local value
  for key in "$@"; do
    value="${!key:-}"
    if [ -n "$value" ]; then
      printf '%s' "$value"
      return 0
    fi
  done
  return 1
}

_export_alias() {
  local target="$1"
  shift
  local resolved
  if resolved="$(_first_nonempty "$@")"; then
    export "${target}=${resolved}"
  fi
}

# Docker
_export_alias DOCKER_USERNAME DOCKER_USERNAME
_export_alias DOCKER_REGISTRY DOCKER_REGISTRY DOCKER_IMAGE_REGISTRY

# Derive JWT public key from private key when missing
if [ -z "${JWT_PUBLIC_KEY:-}" ] && [ -n "${JWT_PRIVATE_KEY:-}" ]; then
  JWT_PUBLIC_KEY="$(printf '%s' "$JWT_PRIVATE_KEY" | openssl rsa -pubout 2>/dev/null || true)"
  export JWT_PUBLIC_KEY
fi
if [ -z "${JWT_PUBLIC_KEY:-}" ] && [ -f "${ROOT_DIR}/jwt-private.pem" ]; then
  JWT_PUBLIC_KEY="$(openssl rsa -in "${ROOT_DIR}/jwt-private.pem" -pubout 2>/dev/null || true)"
  export JWT_PUBLIC_KEY
fi

# JWT — accept both legacy TOKEN_* and current names
_export_alias JWT_ISSUER JWT_ISSUER JWT_TOKEN_ISSUER
_export_alias JWT_AUDIENCE JWT_AUDIENCE JWT_TOKEN_AUDIENCE
_export_alias JWT_ALGORITHM JWT_ALGORITHM
if [ -n "${JWT_PRIVATE_KEY:-}" ] || [ -f "${ROOT_DIR}/jwt-private.pem" ]; then
  export JWT_ALGORITHM="RS256"
else
  export JWT_ALGORITHM="${JWT_ALGORITHM:-RS256}"
fi
_export_alias JWT_ACTIVE_KID JWT_ACTIVE_KID
export JWT_ACTIVE_KID="${JWT_ACTIVE_KID:-default}"
_export_alias JWT_ACCESS_TOKEN_EXPIRES_MINUTES JWT_ACCESS_TOKEN_EXPIRES_MINUTES
export JWT_ACCESS_TOKEN_EXPIRES_MINUTES="${JWT_ACCESS_TOKEN_EXPIRES_MINUTES:-60}"

# S3 — map AWS_S3_* GitHub vars to code names
_export_alias S3_UPLOAD_BUCKET S3_UPLOAD_BUCKET AWS_S3_VIDEO_BUCKET AWS_S3_BUCKET S3_BUCKET_NAME
_export_alias S3_AUDIO_BUCKET S3_AUDIO_BUCKET AWS_S3_AUDIO_BUCKET
_export_alias S3_BUCKET_NAME S3_BUCKET_NAME AWS_S3_BUCKET S3_UPLOAD_BUCKET

# RabbitMQ queues
_export_alias VIDEO_UPLOAD_QUEUE VIDEO_UPLOAD_QUEUE RABBITMQ_QUEUE
export VIDEO_UPLOAD_QUEUE="${VIDEO_UPLOAD_QUEUE:-video-upload-queue}"
_export_alias NOTIFICATION_QUEUE NOTIFICATION_QUEUE RABBITMQ_NOTIFICATION_QUEUE
export NOTIFICATION_QUEUE="${NOTIFICATION_QUEUE:-notification-queue}"
_export_alias GATEWAY_EVENTS_QUEUE GATEWAY_EVENTS_QUEUE
export GATEWAY_EVENTS_QUEUE="${GATEWAY_EVENTS_QUEUE:-gateway-events-queue}"
_export_alias VIDEO_UPLOAD_RETRY_QUEUE VIDEO_UPLOAD_RETRY_QUEUE
export VIDEO_UPLOAD_RETRY_QUEUE="${VIDEO_UPLOAD_RETRY_QUEUE:-video-upload-retry-queue}"
_export_alias VIDEO_UPLOAD_DLQ VIDEO_UPLOAD_DLQ
export VIDEO_UPLOAD_DLQ="${VIDEO_UPLOAD_DLQ:-video-upload-dlq}"
_export_alias VIDEO_COMPLETED_QUEUE VIDEO_COMPLETED_QUEUE
export VIDEO_COMPLETED_QUEUE="${VIDEO_COMPLETED_QUEUE:-video-completed-queue}"
_export_alias VIDEO_FAILED_QUEUE VIDEO_FAILED_QUEUE
export VIDEO_FAILED_QUEUE="${VIDEO_FAILED_QUEUE:-video-failed-queue}"

# Service hosts/ports — align GH naming with docker-compose
_export_alias AUTH_SERVICE_HOST AUTH_SERVICE_HOST AUTH_HOST GATEWAY_SERVICE_HOST
export AUTH_SERVICE_HOST="${AUTH_SERVICE_HOST:-auth-service}"
_export_alias AUTH_SERVICE_PORT AUTH_SERVICE_PORT AUTH_PORT AUTH_SERVICE_PORT
export AUTH_SERVICE_PORT="${AUTH_SERVICE_PORT:-8001}"
_export_alias CONVERTER_SERVICE_HOST CONVERTER_SERVICE_HOST CONVERTER_HOST
export CONVERTER_SERVICE_HOST="${CONVERTER_SERVICE_HOST:-converter-service}"
_export_alias CONVERTER_SERVICE_PORT CONVERTER_SERVICE_PORT CONVERTER_PORT CONVERTER_SERVICE_PORT
export CONVERTER_SERVICE_PORT="${CONVERTER_SERVICE_PORT:-8002}"
_export_alias GATEWAY_PORT GATEWAY_PORT GATEWAY_SERVICE_PORT
export GATEWAY_PORT="${GATEWAY_PORT:-8080}"

# Terraform defaults (safe fallbacks when GH vars not set)
export VPC_CIDR="${VPC_CIDR:-10.0.0.0/16}"
export PUBLIC_SUBNET_CIDRS="${PUBLIC_SUBNET_CIDRS:-[\"10.0.1.0/24\",\"10.0.2.0/24\"]}"
export AVAILABILITY_ZONES="${AVAILABILITY_ZONES:-[\"eu-central-1a\",\"eu-central-1b\"]}"
export ECR_REPOSITORIES="${ECR_REPOSITORIES:-[\"gateway-service\",\"auth-service\",\"converter-service\",\"notification-service\"]}"
export JENKINS_INSTANCE_TYPE="${JENKINS_INSTANCE_TYPE:-t3.medium}"
export JENKINS_ASG_NAME="${JENKINS_ASG_NAME:-${PROJECT_NAME:-video-processing}-jenkins-asg}"
export STRESS_TEST_REQUEST_COUNT="${STRESS_TEST_REQUEST_COUNT:-10}"
export RABBITMQ_TEST_MESSAGE_COUNT="${RABBITMQ_TEST_MESSAGE_COUNT:-5}"
export CLUSTER_AUTOSCALER_HELM_REPOSITORY="${CLUSTER_AUTOSCALER_HELM_REPOSITORY:-https://kubernetes.github.io/autoscaler}"
export CLUSTER_AUTOSCALER_HELM_CHART="${CLUSTER_AUTOSCALER_HELM_CHART:-cluster-autoscaler}"
export CLUSTER_AUTOSCALER_RELEASE_NAME="${CLUSTER_AUTOSCALER_RELEASE_NAME:-cluster-autoscaler}"
export DATABASE_NAMESPACE="${DATABASE_NAMESPACE:-database}"
export MONGODB_RELEASE_NAME="${MONGODB_RELEASE_NAME:-mongodb}"
export POSTGRESQL_RELEASE_NAME="${POSTGRESQL_RELEASE_NAME:-postgresql}"
export RABBITMQ_RELEASE_NAME="${RABBITMQ_RELEASE_NAME:-rabbitmq}"
export MESSAGING_NAMESPACE="${MESSAGING_NAMESPACE:-messaging}"
export CLUSTER_AUTOSCALER_ENABLED="${CLUSTER_AUTOSCALER_ENABLED:-true}"

# Toolchain URL defaults
export UBUNTU_AMI_OWNERS="${UBUNTU_AMI_OWNERS:-[\"099720109477\"]}"
export UBUNTU_AMI_NAME_FILTER="${UBUNTU_AMI_NAME_FILTER:-[\"ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*\"]}"
export DOCKER_GPG_URL="${DOCKER_GPG_URL:-https://download.docker.com/linux/ubuntu/gpg}"
export DOCKER_REPO_URL="${DOCKER_REPO_URL:-https://download.docker.com/linux/ubuntu}"
export JENKINS_GPG_URL="${JENKINS_GPG_URL:-https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key}"
export JENKINS_REPO_URL="${JENKINS_REPO_URL:-https://pkg.jenkins.io/debian-stable binary/}"
export AWSCLI_ZIP_URL="${AWSCLI_ZIP_URL:-https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip}"
export KUBECTL_STABLE_URL="${KUBECTL_STABLE_URL:-https://dl.k8s.io/release/stable.txt}"
export KUBECTL_BINARY_BASE_URL="${KUBECTL_BINARY_BASE_URL:-https://dl.k8s.io/release}"
export HELM_INSTALL_SCRIPT_URL="${HELM_INSTALL_SCRIPT_URL:-https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3}"
export HASHICORP_GPG_URL="${HASHICORP_GPG_URL:-https://apt.releases.hashicorp.com/gpg}"
export HASHICORP_REPO_URL="${HASHICORP_REPO_URL:-https://apt.releases.hashicorp.com}"
export EKSCTL_DOWNLOAD_URL="${EKSCTL_DOWNLOAD_URL:-https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_Linux_amd64.tar.gz}"
export JENKINS_CONTAINER_IMAGE="${JENKINS_CONTAINER_IMAGE:-jenkins/jenkins:lts}"
export JENKINS_CONTAINER_NAME="${JENKINS_CONTAINER_NAME:-jenkins}"
export JENKINS_VOLUME_NAME="${JENKINS_VOLUME_NAME:-jenkins-data}"
export JENKINS_HOST_PORT="${JENKINS_HOST_PORT:-8080}"
export JENKINS_AGENT_PORT="${JENKINS_AGENT_PORT:-50000}"
export JENKINS_ROOT_VOLUME_SIZE="${JENKINS_ROOT_VOLUME_SIZE:-50}"

# SMTP alias
_export_alias SMTP_EMAIL SMTP_EMAIL SMTP_USERNAME
_export_alias SMTP_USERNAME SMTP_USERNAME SMTP_EMAIL
_export_alias SMTP_FROM_EMAIL SMTP_FROM_EMAIL SMTP_EMAIL SMTP_USERNAME

export DOCKER_REGISTRY_SECRET_NAME="${DOCKER_REGISTRY_SECRET_NAME:-docker-registry-secret}"
export DOCKER_IMAGE_REGISTRY="${DOCKER_IMAGE_REGISTRY:-${DOCKER_REGISTRY:-docker.io}}"
export DOCKER_IMAGE_NAMESPACE="${DOCKER_IMAGE_NAMESPACE:-${DOCKER_USERNAME:-}}"
export IMAGE_TAG="${IMAGE_TAG:-${DOCKER_IMAGE_TAG:-latest}}"

export POSTGRES_HOST="${POSTGRES_HOST:-postgres}"
export POSTGRES_PORT="${POSTGRES_PORT:-5432}"
export POSTGRES_USER="${POSTGRES_USER:-postgres}"
export POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-postgres}"
export POSTGRES_DB="${POSTGRES_DB:-video_to_audio_converter}"
export POSTGRES_SSL_MODE="${POSTGRES_SSL_MODE:-disable}"
export RABBITMQ_USERNAME="${RABBITMQ_USERNAME:-${RABBITMQ_DEFAULT_USER:-guest}}"
export RABBITMQ_PASSWORD="${RABBITMQ_PASSWORD:-${RABBITMQ_DEFAULT_PASS:-guest}}"
export RABBITMQ_DEFAULT_USER="${RABBITMQ_DEFAULT_USER:-guest}"
export RABBITMQ_DEFAULT_PASS="${RABBITMQ_DEFAULT_PASS:-guest}"
export MONGO_USERNAME="${MONGO_USERNAME:-mongo}"
export MONGO_PASSWORD="${MONGO_PASSWORD:-mongo}"
export MONGO_DATABASE="${MONGO_DATABASE:-video_converter}"
export MONGO_PORT="${MONGO_PORT:-27017}"
