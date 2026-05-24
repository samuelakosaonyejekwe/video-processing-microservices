#!/bin/bash

echo "Deploying MongoDB Helm Chart..."
helm install mongodb ./infrastructure/helm/mongodb

echo "Deploying PostgreSQL Helm Chart..."
helm install postgresql ./infrastructure/helm/postgresql

echo "Deploying RabbitMQ Helm Chart..."
helm install rabbitmq ./infrastructure/helm/rabbitmq

echo "Helm deployments completed."