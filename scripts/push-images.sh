#!/bin/bash

set -e

if [ -z "$DOCKER_USERNAME" ]; then
  echo "ERROR: DOCKER_USERNAME is not set."
  exit 1
fi

IMAGE_TAG="${IMAGE_TAG:-latest}"
DOCKER_REGISTRY="${DOCKER_REGISTRY:-docker.io}"
IMAGE_PREFIX="${DOCKER_REGISTRY%/}/$DOCKER_USERNAME"

echo "Tagging Docker images with ${IMAGE_TAG}..."

docker tag gateway-service:latest "${IMAGE_PREFIX}/gateway-service:${IMAGE_TAG}"
docker tag auth-service:latest "${IMAGE_PREFIX}/auth-service:${IMAGE_TAG}"
docker tag converter-service:latest "${IMAGE_PREFIX}/converter-service:${IMAGE_TAG}"
docker tag notification-service:latest "${IMAGE_PREFIX}/notification-service:${IMAGE_TAG}"

echo "Pushing Docker images..."

docker push "${IMAGE_PREFIX}/gateway-service:${IMAGE_TAG}"
docker push "${IMAGE_PREFIX}/auth-service:${IMAGE_TAG}"
docker push "${IMAGE_PREFIX}/converter-service:${IMAGE_TAG}"
docker push "${IMAGE_PREFIX}/notification-service:${IMAGE_TAG}"

echo "Docker images pushed successfully."