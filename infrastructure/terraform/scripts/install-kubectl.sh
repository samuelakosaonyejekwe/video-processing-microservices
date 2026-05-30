#!/bin/bash

set -euo pipefail

: "${KUBECTL_STABLE_URL:?Missing KUBECTL_STABLE_URL}"

: "${KUBECTL_BINARY_BASE_URL:?Missing KUBECTL_BINARY_BASE_URL}"

KUBECTL_VERSION=$(curl -s "${KUBECTL_STABLE_URL}")

curl -LO \
  "${KUBECTL_BINARY_BASE_URL}/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"

chmod +x kubectl

mv kubectl /usr/local/bin/