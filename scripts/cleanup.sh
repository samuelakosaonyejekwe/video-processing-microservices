#!/bin/bash

set -euo pipefail

# By default prune only dangling images (safe). Pass --all/-a to prune ALL
# unused images. Pass --yes/-y to skip the confirmation prompt (e.g. in CI).
PRUNE_ALL=""
ASSUME_YES=""
for arg in "$@"; do
  case "${arg}" in
    --all|-a)  PRUNE_ALL="-a" ;;
    --yes|-y)  ASSUME_YES="yes" ;;
  esac
done

if [ "${ASSUME_YES}" != "yes" ]; then
  if [ -t 0 ]; then
    if [ -n "${PRUNE_ALL}" ]; then
      echo "This will remove ALL unused Docker images, networks, and dangling volumes."
    else
      echo "This will remove dangling Docker images, unused networks, and dangling volumes."
    fi
    printf "Type 'yes' to continue: "
    read -r reply
    if [ "${reply}" != "yes" ]; then
      echo "Aborted."
      exit 1
    fi
  else
    echo "ERROR: refusing to prune non-interactively. Pass --yes to proceed." >&2
    exit 1
  fi
fi

echo "Cleaning unused Docker resources..."

docker system prune ${PRUNE_ALL} -f

echo "Removing dangling volumes..."

docker volume prune -f

echo "Cleanup completed successfully."
