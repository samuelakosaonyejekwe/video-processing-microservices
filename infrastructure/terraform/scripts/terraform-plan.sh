#!/bin/bash

set -euo pipefail

cd infrastructure/terraform

terraform plan -input=false -parallelism=30 -lock-timeout=10m -out=tfplan
