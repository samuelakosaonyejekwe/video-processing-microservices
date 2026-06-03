#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=scripts/lib/env-aliases.sh
source "${ROOT_DIR}/scripts/lib/env-aliases.sh"

kubectl delete pod \
  -l "app.kubernetes.io/name=${CONVERTER_APP_NAME}" \
  -n "${APPLICATION_NAMESPACE}"