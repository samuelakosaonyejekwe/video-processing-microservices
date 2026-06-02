#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

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

: "${AWS_REGION:?Missing AWS_REGION}"
: "${PROJECT_NAME:?Missing PROJECT_NAME}"
: "${APP_ENV:?Missing APP_ENV}"
: "${EKS_CLUSTER_NAME:?Missing EKS_CLUSTER_NAME}"
: "${EKS_NODE_GROUP_NAME:?Missing EKS_NODE_GROUP_NAME}"
: "${EKS_INSTANCE_TYPE:?Missing EKS_INSTANCE_TYPE}"
: "${EKS_DESIRED_SIZE:?Missing EKS_DESIRED_SIZE}"
: "${EKS_MIN_SIZE:?Missing EKS_MIN_SIZE}"
: "${EKS_MAX_SIZE:?Missing EKS_MAX_SIZE}"
: "${TF_STATE_BUCKET:?Missing TF_STATE_BUCKET}"
: "${TF_LOCK_TABLE:?Missing TF_LOCK_TABLE}"

# Terraform-specific defaults sourced from GitHub vars or safe fallbacks
export EKS_NODE_INSTANCE_TYPE="${EKS_NODE_INSTANCE_TYPE:-${EKS_INSTANCE_TYPE}}"
export PRIVATE_SUBNET_CIDRS="${PRIVATE_SUBNET_CIDRS:-}"
export ALLOWED_CIDR_BLOCKS="${ALLOWED_CIDR_BLOCKS:-[\"0.0.0.0/0\"]}"
export PUBLIC_ACCESS_CIDRS="${PUBLIC_ACCESS_CIDRS:-[\"0.0.0.0/0\"]}"
export KUBERNETES_VERSION="${KUBERNETES_VERSION:-1.31}"
export ENABLE_CLUSTER_LOG_TYPES="${ENABLE_CLUSTER_LOG_TYPES:-[\"api\",\"audit\"]}"
export ENDPOINT_PRIVATE_ACCESS="${ENDPOINT_PRIVATE_ACCESS:-true}"
export ENDPOINT_PUBLIC_ACCESS="${ENDPOINT_PUBLIC_ACCESS:-true}"
export NODE_DISK_SIZE="${NODE_DISK_SIZE:-50}"
export CAPACITY_TYPE="${CAPACITY_TYPE:-ON_DEMAND}"
export AMI_TYPE="${AMI_TYPE:-AL2_x86_64}"
export MAX_UNAVAILABLE="${MAX_UNAVAILABLE:-1}"
export KEDA_RELEASE_NAME="${KEDA_RELEASE_NAME:-keda}"
export KEDA_HELM_REPOSITORY="${KEDA_HELM_REPOSITORY:-https://kedacore.github.io/charts}"
export KEDA_CHART_NAME="${KEDA_CHART_NAME:-keda}"
export KEDA_NAMESPACE="${KEDA_NAMESPACE:-keda}"
export DOMAIN_NAME="${DOMAIN_NAME:-${APP_DOMAIN:-api.example.com}}"
export HOSTED_ZONE_NAME="${HOSTED_ZONE_NAME:-${APP_DOMAIN:-example.com}}"
export ACM_CERTIFICATE_ARN="${ACM_CERTIFICATE_ARN:-arn:aws:acm:${AWS_REGION}:000000000000:certificate/placeholder}"
export S3_BUCKET_NAME="${S3_BUCKET_NAME:-${S3_UPLOAD_BUCKET:-${AWS_S3_VIDEO_BUCKET:-${AWS_S3_BUCKET:-}}}}"
export S3_VIDEO_BUCKET_NAME="${S3_VIDEO_BUCKET_NAME:-${S3_UPLOAD_BUCKET:-${AWS_S3_VIDEO_BUCKET:-${S3_BUCKET_NAME:-}}}}"
export S3_AUDIO_BUCKET_NAME="${S3_AUDIO_BUCKET_NAME:-${S3_AUDIO_BUCKET:-${AWS_S3_AUDIO_BUCKET:-}}}"
export KUBERNETES_NAMESPACE="${KUBERNETES_NAMESPACE:-${K8S_NAMESPACE:-video-processing}}"
export CLUSTER_NAME="${CLUSTER_NAME:-${EKS_CLUSTER_NAME}}"
export CLUSTER_VERSION="${CLUSTER_VERSION:-${KUBERNETES_VERSION}}"

mkdir -p infrastructure/terraform

cat > infrastructure/terraform/terraform.tfvars <<EOF
project_name          = "${PROJECT_NAME}"
environment           = "${APP_ENV}"
aws_region            = "${AWS_REGION}"
eks_cluster_name      = "${EKS_CLUSTER_NAME}"
eks_node_group_name   = "${EKS_NODE_GROUP_NAME}"
eks_node_instance_type = "${EKS_NODE_INSTANCE_TYPE}"
eks_desired_size      = ${EKS_DESIRED_SIZE}
eks_min_size          = ${EKS_MIN_SIZE}
eks_max_size          = ${EKS_MAX_SIZE}
vpc_cidr              = "${VPC_CIDR}"
availability_zones    = ${AVAILABILITY_ZONES}
public_subnet_cidrs   = ${PUBLIC_SUBNET_CIDRS}
private_subnet_cidrs  = ${PRIVATE_SUBNET_CIDRS}
enable_nat_gateway    = true
single_nat_gateway    = true
allowed_cidr_blocks   = ${ALLOWED_CIDR_BLOCKS}
kubernetes_version    = "${KUBERNETES_VERSION}"
enable_cluster_log_types = ${ENABLE_CLUSTER_LOG_TYPES}
endpoint_private_access = ${ENDPOINT_PRIVATE_ACCESS}
endpoint_public_access  = ${ENDPOINT_PUBLIC_ACCESS}
public_access_cidrs   = ${PUBLIC_ACCESS_CIDRS}
node_disk_size        = ${NODE_DISK_SIZE}
capacity_type         = "${CAPACITY_TYPE}"
ami_type              = "${AMI_TYPE}"
max_unavailable       = ${MAX_UNAVAILABLE}
jenkins_instance_type = "${JENKINS_INSTANCE_TYPE}"
keda_release_name     = "${KEDA_RELEASE_NAME}"
keda_helm_repository  = "${KEDA_HELM_REPOSITORY}"
keda_chart_name       = "${KEDA_CHART_NAME}"
keda_namespace        = "${KEDA_NAMESPACE}"
domain_name           = "${DOMAIN_NAME}"
hosted_zone_name      = "${HOSTED_ZONE_NAME}"
acm_certificate_arn   = "${ACM_CERTIFICATE_ARN}"
s3_bucket_name        = "${S3_BUCKET_NAME}"
s3_video_bucket_name  = "${S3_VIDEO_BUCKET_NAME}"
s3_audio_bucket_name  = "${S3_AUDIO_BUCKET_NAME}"
s3_buckets = {
  video = {
    bucket_name = "${S3_VIDEO_BUCKET_NAME}"
    enable_cors = true
    prefix_lifecycle_rules = [
      {
        id              = "expire-uploaded-videos"
        prefix          = "uploads/videos/"
        expiration_days = ${S3_VIDEO_UPLOAD_EXPIRATION_DAYS:-7}
      }
    ]
  }
  audio = {
    bucket_name = "${S3_AUDIO_BUCKET_NAME}"
    prefix_lifecycle_rules = [
      {
        id              = "expire-converted-audio"
        prefix          = "outputs/audio/"
        expiration_days = ${S3_AUDIO_OUTPUT_EXPIRATION_DAYS:-7}
      }
    ]
  }
}
kubernetes_namespace  = "${KUBERNETES_NAMESPACE}"
ecr_repositories      = ${ECR_REPOSITORIES}
ubuntu_ami_owners     = ${UBUNTU_AMI_OWNERS}
ubuntu_ami_name_filter = ${UBUNTU_AMI_NAME_FILTER}
docker_gpg_url        = "${DOCKER_GPG_URL}"
docker_repo_url       = "${DOCKER_REPO_URL}"
jenkins_gpg_url       = "${JENKINS_GPG_URL}"
jenkins_repo_url      = "${JENKINS_REPO_URL}"
awscli_zip_url        = "${AWSCLI_ZIP_URL}"
kubectl_stable_url    = "${KUBECTL_STABLE_URL}"
kubectl_binary_base_url = "${KUBECTL_BINARY_BASE_URL}"
helm_install_script_url = "${HELM_INSTALL_SCRIPT_URL}"
hashicorp_gpg_url     = "${HASHICORP_GPG_URL}"
hashicorp_repo_url    = "${HASHICORP_REPO_URL}"
eksctl_download_url   = "${EKSCTL_DOWNLOAD_URL}"
jenkins_container_image = "${JENKINS_CONTAINER_IMAGE}"
jenkins_container_name = "${JENKINS_CONTAINER_NAME}"
jenkins_volume_name   = "${JENKINS_VOLUME_NAME}"
jenkins_host_port     = ${JENKINS_HOST_PORT}
jenkins_agent_port    = ${JENKINS_AGENT_PORT}
jenkins_root_volume_size = ${JENKINS_ROOT_VOLUME_SIZE}
cluster_autoscaler_release_name = "${CLUSTER_AUTOSCALER_RELEASE_NAME}"
cluster_autoscaler_repository = "${CLUSTER_AUTOSCALER_HELM_REPOSITORY}"
cluster_autoscaler_chart = "${CLUSTER_AUTOSCALER_HELM_CHART}"
cluster_autoscaler_namespace = "${KUBE_SYSTEM_NAMESPACE:-kube-system}"
cluster_autoscaler_timeout = 600
aws_load_balancer_controller_name = "aws-load-balancer-controller"
aws_load_balancer_controller_repository = "https://aws.github.io/eks-charts"
aws_load_balancer_controller_chart = "aws-load-balancer-controller"
aws_load_balancer_controller_namespace = "kube-system"
tags = {
  Project     = "${PROJECT_NAME}"
  Environment = "${APP_ENV}"
  ManagedBy   = "Terraform"
  Application = "VideoConverter"
}
EOF

echo "terraform.tfvars generated successfully"
terraform fmt infrastructure/terraform/terraform.tfvars
