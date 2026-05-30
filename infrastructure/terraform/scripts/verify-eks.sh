#!/bin/bash

set -euo pipefail

kubectl get nodes

kubectl get pods -A

kubectl get svc -A

kubectl get ingress -A

if kubectl top nodes >/dev/null 2>&1; then
  kubectl top nodes
  kubectl top pods -A
else
  echo "metrics-server not ready yet; skipping kubectl top"
fi