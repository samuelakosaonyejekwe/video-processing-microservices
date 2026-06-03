#!/bin/bash

set -euo pipefail

echo "=========================================="
echo "DISCOVERING ENVIRONMENT VARIABLES"
echo "=========================================="

echo ""

echo "Scanning project for environment variables..."

grep -RhoE '\${[A-Z0-9_]+}' . \
  --exclude-dir=.git \
  --exclude-dir=node_modules \
  --exclude-dir=venv \
  | sed 's/[${}]//g' \
  | sort -u > discovered-vars.txt

echo ""
echo "=========================================="
echo "DISCOVERED VARIABLES"
echo "=========================================="

cat discovered-vars.txt

echo ""
echo "=========================================="
echo "TOTAL VARIABLES FOUND"
echo "=========================================="

wc -l discovered-vars.txt

echo ""
echo "=========================================="
echo "GENERATING .env.example"
echo "=========================================="

> .env.example

while read VAR
do
  echo "${VAR}=" >> .env.example
done < discovered-vars.txt

echo ""
echo ".env.example generated successfully"

echo ""
echo "=========================================="
echo "DONE"
echo "=========================================="