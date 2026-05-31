#!/bin/bash

set -euo pipefail

# shellcheck source=scripts/lib/env-aliases.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/lib/env-aliases.sh"

KEDA_WAIT_TIMEOUT="${KEDA_SCALEDOBJECT_WAIT_TIMEOUT:-120s}"

kubectl get pods \
  -n "${KEDA_NAMESPACE}"

kubectl get scaledobjects \
  -A

kubectl get triggerauthentications \
  -A

kubectl describe scaledobject \
  "${CONVERTER_SCALEDOBJECT_NAME}" \
  -n "${K8S_NAMESPACE}"

kubectl wait --for=condition=Ready \
  "scaledobject/${CONVERTER_SCALEDOBJECT_NAME}" \
  -n "${K8S_NAMESPACE}" \
  --timeout="${KEDA_WAIT_TIMEOUT}"

echo "KEDA validation completed successfully."
