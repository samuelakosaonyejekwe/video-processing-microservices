#!/bin/bash

set -euo pipefail

: "${HASHICORP_GPG_URL:?Missing HASHICORP_GPG_URL}"

: "${HASHICORP_REPO_URL:?Missing HASHICORP_REPO_URL}"

install -m 0755 -d /etc/apt/keyrings

curl -fsSL "${HASHICORP_GPG_URL}" | \
  gpg --dearmor \
  -o /etc/apt/keyrings/hashicorp-archive-keyring.gpg

echo \
  "deb [signed-by=/etc/apt/keyrings/hashicorp-archive-keyring.gpg] ${HASHICORP_REPO_URL} $(lsb_release -cs) main" | \
  tee /etc/apt/sources.list.d/hashicorp.list

apt-get update -y

apt-get install -y terraform