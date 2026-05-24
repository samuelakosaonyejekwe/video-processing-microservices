#!/bin/bash

DOCKER_USERNAME="your-dockerhub-username"

docker tag gateway-service $DOCKER_USERNAME/gateway-service:latest
docker tag auth-service $DOCKER_USERNAME/auth-service:latest
docker tag converter-service $DOCKER_USERNAME/converter-service:latest
docker tag notification-service $DOCKER_USERNAME/notification-service:latest

docker push $DOCKER_USERNAME/gateway-service:latest
docker push $DOCKER_USERNAME/auth-service:latest
docker push $DOCKER_USERNAME/converter-service:latest
docker push $DOCKER_USERNAME/notification-service:latest

echo "Docker images pushed successfully."