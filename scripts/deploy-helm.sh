#!/bin/bash

set -euo pipefail

helm repo update

if [ "${CLUSTER_AUTOSCALER_ENABLED}" = "true" ]; then

  chmod +x scripts/deploy-cluster-autoscaler.sh

  bash scripts/deploy-cluster-autoscaler.sh

fi

echo "Deploying MongoDB Helm Chart..."

helm upgrade --install ${MONGODB_RELEASE_NAME} \
  ./infrastructure/helm/mongodb \
  --namespace ${DATABASE_NAMESPACE} \
  --create-namespace

echo "Deploying PostgreSQL Helm Chart..."

helm upgrade --install ${POSTGRESQL_RELEASE_NAME} \
  ./infrastructure/helm/postgresql \
  --namespace ${DATABASE_NAMESPACE} \
  --create-namespace

echo "Deploying RabbitMQ Helm Chart..."

helm upgrade --install ${RABBITMQ_RELEASE_NAME} \
  ./infrastructure/helm/rabbitmq \
  --namespace ${MESSAGING_NAMESPACE} \
  --create-namespace

echo "Helm deployments completed."