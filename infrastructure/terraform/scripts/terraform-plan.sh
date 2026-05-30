#!/bin/bash

set -euo pipefail

terraform init

terraform fmt -recursive

terraform validate

terraform plan