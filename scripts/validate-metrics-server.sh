#!/bin/bash

set -euo pipefail

kubectl get deployment \
  metrics-server \
  -n ${KUBE_SYSTEM_NAMESPACE}

kubectl get apiservices | grep metrics

kubectl top nodes

kubectl top pods -A

echo "Metrics server validation completed successfully."