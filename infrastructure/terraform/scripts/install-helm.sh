#!/bin/bash

set -euo pipefail

: "${HELM_INSTALL_SCRIPT_URL:?Missing HELM_INSTALL_SCRIPT_URL}"

curl "${HELM_INSTALL_SCRIPT_URL}" | bash