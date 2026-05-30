#!/bin/bash

set -euo pipefail

kubectl delete pod \
-l app.kubernetes.io/name=${CONVERTER_APP_NAME} \
-n ${APPLICATION_NAMESPACE}