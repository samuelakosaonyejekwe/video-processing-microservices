#!/bin/bash

set -euo pipefail

cd infrastructure/terraform

if [ ! -f tfplan ]; then
  echo "ERROR: tfplan not found. Run terraform-plan.sh first."
  exit 1
fi

terraform apply -auto-approve tfplan
