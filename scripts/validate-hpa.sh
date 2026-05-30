#!/bin/bash

set -euo pipefail

kubectl get hpa -A

kubectl describe hpa \
  -n ${K8S_NAMESPACE}

kubectl top pods \
  -n ${K8S_NAMESPACE}

echo "HPA validation completed successfully."