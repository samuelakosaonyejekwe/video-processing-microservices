#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Accept --yes / -y as a non-interactive confirmation (maps to CONFIRM_DESTROY).
for arg in "$@"; do
  case "${arg}" in
    --yes|-y) export CONFIRM_DESTROY=yes ;;
  esac
done

# shellcheck source=scripts/lib/confirm-destructive.sh
source "${ROOT_DIR}/scripts/lib/confirm-destructive.sh"
confirm_destructive "terraform destroy the dev cluster (all managed infrastructure)"

terraform -chdir=infrastructure/terraform destroy \
  -var-file=environments/dev.tfvars \
  -auto-approve
