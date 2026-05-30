#!/bin/bash

set -e

apt update -y

apt install -y \
  docker.io \
  docker-compose \
  git

systemctl enable docker

systemctl start docker

mkdir -p /opt/platform

cd /opt/platform

git clone https://github.com/${github_repository}.git

cd microservices-video-to-converter-app/infrastructure/jenkins

docker compose up -d --build