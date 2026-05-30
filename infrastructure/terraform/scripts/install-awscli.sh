#!/bin/bash

set -euo pipefail

: "${AWSCLI_ZIP_URL:?Missing AWSCLI_ZIP_URL}"

curl "${AWSCLI_ZIP_URL}" \
  -o awscliv2.zip

unzip awscliv2.zip

./aws/install