#!/bin/bash

set -euo pipefail

cd infrastructure/terraform

terraform destroy \
  -input=false \
  -auto-approve