#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

# shellcheck source=scripts/lib/env-aliases.sh
source "${ROOT_DIR}/scripts/lib/env-aliases.sh"

if [ -f "${ROOT_DIR}/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  source "${ROOT_DIR}/.env"
  set +a
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

mkdir -p infrastructure/terraform

cat > infrastructure/terraform/terraform.tfvars <<EOF
aws_region = "${AWS_REGION}"

project_name = "${PROJECT_NAME}"

environment = "${APP_ENV}"

eks_cluster_name = "${EKS_CLUSTER_NAME}"

node_group_name = "${EKS_NODE_GROUP_NAME}"

instance_type = "${EKS_INSTANCE_TYPE}"

desired_size = ${EKS_DESIRED_SIZE}

min_size = ${EKS_MIN_SIZE}

max_size = ${EKS_MAX_SIZE}

vpc_cidr = "${VPC_CIDR}"

public_subnet_cidrs = ${PUBLIC_SUBNET_CIDRS}

availability_zones = ${AVAILABILITY_ZONES}

tf_state_bucket = "${TF_STATE_BUCKET}"

tf_lock_table = "${TF_LOCK_TABLE}"

ecr_repositories = ${ECR_REPOSITORIES}

jenkins_instance_type = "${JENKINS_INSTANCE_TYPE}"

ubuntu_ami_owners = ${UBUNTU_AMI_OWNERS}

ubuntu_ami_name_filter = "${UBUNTU_AMI_NAME_FILTER}"

docker_gpg_url = "${DOCKER_GPG_URL}"

docker_repo_url = "${DOCKER_REPO_URL}"

jenkins_gpg_url = "${JENKINS_GPG_URL}"

jenkins_repo_url = "${JENKINS_REPO_URL}"

awscli_zip_url = "${AWSCLI_ZIP_URL}"

kubectl_stable_url = "${KUBECTL_STABLE_URL}"

kubectl_binary_base_url = "${KUBECTL_BINARY_BASE_URL}"

helm_install_script_url = "${HELM_INSTALL_SCRIPT_URL}"

hashicorp_gpg_url = "${HASHICORP_GPG_URL}"

hashicorp_repo_url = "${HASHICORP_REPO_URL}"

eksctl_download_url = "${EKSCTL_DOWNLOAD_URL}"

jenkins_container_image = "${JENKINS_CONTAINER_IMAGE}"

jenkins_container_name = "${JENKINS_CONTAINER_NAME}"

jenkins_volume_name = "${JENKINS_VOLUME_NAME}"

jenkins_host_port = ${JENKINS_HOST_PORT}

jenkins_agent_port = ${JENKINS_AGENT_PORT}

jenkins_root_volume_size = ${JENKINS_ROOT_VOLUME_SIZE}
EOF

echo "terraform.tfvars generated successfully"
terraform fmt terraform.tfvars
