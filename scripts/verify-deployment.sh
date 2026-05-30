#!/bin/bash

set -euo pipefail

kubectl get pods -A

kubectl get deployments -A

kubectl get services -A

kubectl rollout status deployment/gateway \
-n ${K8S_NAMESPACE}