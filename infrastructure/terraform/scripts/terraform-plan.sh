#!/bin/bash

set -euo pipefail

cd infrastructure/terraform

terraform plan
