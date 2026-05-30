#!/bin/bash

set -euo pipefail

helm repo add autoscaler \
  ${CLUSTER_AUTOSCALER_HELM_REPOSITORY}

helm repo update

helm upgrade --install \
  ${CLUSTER_AUTOSCALER_RELEASE_NAME} \
  autoscaler/${CLUSTER_AUTOSCALER_HELM_CHART} \
  --namespace ${KUBE_SYSTEM_NAMESPACE} \
  --create-namespace \
  --set autoDiscovery.clusterName=${EKS_CLUSTER_NAME} \
  --set awsRegion=${AWS_REGION}