#!/bin/bash

set -euo pipefail

terraform -chdir=infrastructure/terraform destroy \
  -var-file=environments/dev.tfvars \
  -auto-approve