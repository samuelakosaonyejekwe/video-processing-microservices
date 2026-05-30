#!/bin/bash

set -euo pipefail

export APP_NAMESPACE="${APP_NAMESPACE}"
export MESSAGING_NAMESPACE="${MESSAGING_NAMESPACE}"
export MONITORING_NAMESPACE="${MONITORING_NAMESPACE}"
export INGRESS_NAMESPACE="${INGRESS_NAMESPACE}"
export JENKINS_NAMESPACE="${JENKINS_NAMESPACE}"

envsubst < infrastructure/kubernetes/namespaces/namespace.yaml | kubectl apply -f -