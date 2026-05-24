#!/bin/bash

kubectl apply -f infrastructure/kubernetes/monitoring/prometheus.yaml

kubectl apply -f infrastructure/kubernetes/monitoring/grafana.yaml

kubectl apply -f infrastructure/kubernetes/monitoring/metrics-server.yaml

echo "Monitoring stack deployed successfully."