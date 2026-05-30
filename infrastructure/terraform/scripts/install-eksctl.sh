#!/bin/bash

set -euo pipefail

: "${EKSCTL_DOWNLOAD_URL:?Missing EKSCTL_DOWNLOAD_URL}"

curl --silent --location \
  "${EKSCTL_DOWNLOAD_URL}" | \
  tar xz -C /tmp

mv /tmp/eksctl /usr/local/bin