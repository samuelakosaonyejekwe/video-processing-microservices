#!/bin/bash

set -euo pipefail

kubectl get pods \
  -n ${KEDA_NAMESPACE}

kubectl get scaledobjects \
  -A

kubectl get triggerauthentications \
  -A

kubectl describe scaledobject \
  ${CONVERTER_SCALEDOBJECT_NAME} \
  -n ${K8S_NAMESPACE}

echo "KEDA validation completed successfully."