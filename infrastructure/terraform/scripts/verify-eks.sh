#!/bin/bash

set -euo pipefail

kubectl get nodes

kubectl get pods -A

kubectl get svc -A

kubectl get ingress -A

kubectl top nodes

kubectl top pods -A