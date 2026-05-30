#!/bin/bash

set -euo pipefail

aws eks update-kubeconfig \
  --region "${AWS_REGION}" \
  --name "${EKS_CLUSTER_NAME}"

helm upgrade --install ${GATEWAY_RELEASE_NAME} \
  ./infrastructure/helm/gateway \
  --namespace "${K8S_NAMESPACE}" \
  --create-namespace

kubectl apply -f infrastructure/kubernetes/

bash scripts/verify-deployment.sh