#!/bin/bash

set -euo pipefail

cd infrastructure/terraform

terraform plan -out=tfplan

terraform apply -auto-approve tfplan
