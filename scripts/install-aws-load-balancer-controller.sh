#!/bin/bash

set -euo pipefail

helm repo add eks ${AWS_EKS_HELM_REPOSITORY}

helm repo update

helm upgrade --install ${AWS_LOAD_BALANCER_CONTROLLER_RELEASE_NAME} \
  eks/${AWS_LOAD_BALANCER_CONTROLLER_HELM_CHART} \
  --namespace ${AWS_LOAD_BALANCER_CONTROLLER_NAMESPACE} \
  --create-namespace \
  --set clusterName=${EKS_CLUSTER_NAME} \
  --set serviceAccount.create=${AWS_LOAD_BALANCER_CONTROLLER_SERVICE_ACCOUNT_CREATE} \
  --set serviceAccount.name=${AWS_LOAD_BALANCER_CONTROLLER_SERVICE_ACCOUNT_NAME} \
  --set region=${AWS_REGION} \
  --set vpcId=${VPC_ID}