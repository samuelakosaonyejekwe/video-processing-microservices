#!/bin/bash

echo "Building Gateway Service Image..."
docker build -t gateway-service ./services/gateway

echo "Building Auth Service Image..."
docker build -t auth-service ./services/auth

echo "Building Converter Service Image..."
docker build -t converter-service ./services/converter

echo "Building Notification Service Image..."
docker build -t notification-service ./services/notification

echo "All Docker images built successfully."