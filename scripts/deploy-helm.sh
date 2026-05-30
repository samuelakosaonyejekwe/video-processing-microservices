#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/env-aliases.sh
source "${ROOT_DIR}/scripts/lib/env-aliases.sh"

export MONGODB_RELEASE_NAME="${MONGODB_RELEASE_NAME:-mongodb}"
export POSTGRESQL_RELEASE_NAME="${POSTGRESQL_RELEASE_NAME:-postgresql}"
export RABBITMQ_RELEASE_NAME="${RABBITMQ_RELEASE_NAME:-rabbitmq}"
export DATABASE_NAMESPACE="${DATABASE_NAMESPACE:-database}"
export MESSAGING_NAMESPACE="${MESSAGING_NAMESPACE:-messaging}"

if [ "${CLUSTER_AUTOSCALER_ENABLED:-true}" = "true" ]; then

  chmod +x scripts/deploy-cluster-autoscaler.sh

  bash scripts/deploy-cluster-autoscaler.sh

fi

echo "Deploying MongoDB Helm Chart..."

helm upgrade --install "${MONGODB_RELEASE_NAME}" \
  "${ROOT_DIR}/infrastructure/helm/mongodb" \
  --namespace "${DATABASE_NAMESPACE}" \
  --create-namespace

echo "Deploying PostgreSQL Helm Chart..."

helm upgrade --install "${POSTGRESQL_RELEASE_NAME}" \
  "${ROOT_DIR}/infrastructure/helm/postgresql" \
  --namespace "${DATABASE_NAMESPACE}" \
  --create-namespace

echo "Deploying RabbitMQ Helm Chart..."

helm upgrade --install "${RABBITMQ_RELEASE_NAME}" \
  "${ROOT_DIR}/infrastructure/helm/rabbitmq" \
  --namespace "${MESSAGING_NAMESPACE}" \
  --create-namespace

echo "Helm deployments completed."