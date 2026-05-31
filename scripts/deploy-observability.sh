#!/bin/bash

set -euo pipefail

if [ -d infrastructure/kubernetes/logging ] && [ "$(ls -A infrastructure/kubernetes/logging 2>/dev/null)" ]; then
  kubectl apply -f infrastructure/kubernetes/logging/
fi

kubectl apply -f infrastructure/kubernetes/tracing/

helm repo add prometheus-community ${PROMETHEUS_HELM_REPOSITORY}

helm repo add grafana ${GRAFANA_HELM_REPOSITORY}

helm repo update

helm upgrade --install ${PROMETHEUS_RELEASE_NAME} \
  prometheus-community/${PROMETHEUS_HELM_CHART} \
  --namespace ${MONITORING_NAMESPACE} \
  --create-namespace \
  -f infrastructure/helm/monitoring/kube-prometheus-stack-values.yaml

helm upgrade --install ${LOKI_RELEASE_NAME} \
  grafana/${LOKI_HELM_CHART} \
  --namespace ${LOGGING_NAMESPACE} \
  --create-namespace \
  -f infrastructure/helm/monitoring/loki-values.yaml

helm upgrade --install ${TEMPO_RELEASE_NAME} \
  grafana/${TEMPO_HELM_CHART} \
  --namespace ${TRACING_NAMESPACE} \
  --create-namespace \
  -f infrastructure/helm/monitoring/tempo-values.yaml

kubectl apply -f infrastructure/kubernetes/monitoring/

kubectl apply -f infrastructure/kubernetes/monitoring/grafana-dashboard-configmap.yaml

kubectl apply \
  -f infrastructure/kubernetes/autoscaling/

kubectl get hpa -A

kubectl get scaledobjects -A