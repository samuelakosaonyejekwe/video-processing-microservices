#!/bin/bash

set -euo pipefail

PROJECT_ROOT="$(pwd)"

mkdir -p security-audit

OUTPUT_FILE="security-audit/final-security-review.txt"

echo "========================================="
echo "RUNNING FULL SECURITY SCAN"
echo "========================================="

grep -RInE \
'(PASSWORD_PATTERN_PLACEHOLDER|AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{36}|BEGIN RSA PRIVATE KEY|BEGIN OPENSSH PRIVATE KEY)' \
services infrastructure tests docker-compose.yml .github Jenkinsfile scripts \
--exclude-dir=.git \
--exclude-dir=node_modules \
--exclude-dir=.venv \
--exclude-dir=venv \
--exclude-dir=dist \
--exclude-dir=build \
--exclude-dir=coverage \
--exclude-dir=security-audit \
--exclude=*.pyc \
--exclude=*.pyo \
--exclude=*.log \
--exclude=.env \
--exclude=full-security-scan.sh \
> "${OUTPUT_FILE}" || true

echo "========================================="
echo "SECURITY SCAN COMPLETE"
echo "========================================="
echo "OUTPUT:"
echo "${OUTPUT_FILE}"

if [ -s "${OUTPUT_FILE}" ]; then
    echo ""
    echo "WARNING: Potential security findings detected."
    echo "Review:"
    echo "${OUTPUT_FILE}"
else
    echo ""
    echo "No obvious hardcoded secrets detected."
fi