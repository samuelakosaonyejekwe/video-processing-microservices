#!/bin/bash

set -euo pipefail

helm repo add external-dns ${EXTERNAL_DNS_HELM_REPOSITORY}

helm repo update

helm upgrade --install ${EXTERNAL_DNS_RELEASE_NAME} \
  external-dns/${EXTERNAL_DNS_HELM_CHART} \
  --namespace ${EXTERNAL_DNS_NAMESPACE} \
  --create-namespace \
  --set provider=${EXTERNAL_DNS_PROVIDER} \
  --set domainFilters[0]=${HOSTED_ZONE_NAME} \
  --set policy=${EXTERNAL_DNS_POLICY} \
  --set registry=${EXTERNAL_DNS_REGISTRY} \
  --set txtOwnerId=${EXTERNAL_DNS_TXT_OWNER_ID}