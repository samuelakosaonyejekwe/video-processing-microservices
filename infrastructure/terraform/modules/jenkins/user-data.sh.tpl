#!/bin/bash

set -euxo pipefail

export DEBIAN_FRONTEND=noninteractive

apt-get update -y

apt-get install -y \
  ca-certificates \
  curl \
  gnupg \
  lsb-release \
  unzip \
  jq \
  git \
  apt-transport-https \
  software-properties-common

install -m 0755 -d /etc/apt/keyrings

curl -fsSL ${docker_gpg_url} | \
  gpg --dearmor -o /etc/apt/keyrings/docker.gpg

chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] ${docker_repo_url} $(lsb_release -cs) stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update -y

apt-get install -y \
  docker-ce \
  docker-ce-cli \
  containerd.io \
  docker-buildx-plugin \
  docker-compose-plugin

systemctl enable docker

systemctl start docker

curl -fsSL ${jenkins_gpg_url} | \
  tee /usr/share/keyrings/jenkins-keyring.asc > /dev/null

echo \
  "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] ${jenkins_repo_url}" | \
  tee /etc/apt/sources.list.d/jenkins.list > /dev/null

apt-get update -y

apt-get install -y \
  fontconfig \
  openjdk-17-jre

curl ${awscli_zip_url} -o awscliv2.zip

unzip awscliv2.zip

./aws/install

KUBECTL_VERSION=$(curl -s ${kubectl_stable_url})

curl -LO \
  "${kubectl_binary_base_url}/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"

chmod +x kubectl

mv kubectl /usr/local/bin/

curl ${helm_install_script_url} | bash

curl -fsSL ${hashicorp_gpg_url} | \
  gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg

echo \
  "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] ${hashicorp_repo_url} $(lsb_release -cs) main" | \
  tee /etc/apt/sources.list.d/hashicorp.list

apt-get update -y

apt-get install -y terraform

curl --silent --location \
  ${eksctl_download_url} | \
  tar xz -C /tmp

mv /tmp/eksctl /usr/local/bin

mkdir -p /opt/jenkins

cat > /opt/jenkins/docker-compose.yml <<EOF
services:

  jenkins:

    image: ${jenkins_container_image}

    container_name: ${jenkins_container_name}

    restart: always

    privileged: true

    user: root

    environment:
      JAVA_OPTS: "-Djenkins.install.runSetupWizard=false"

    ports:
      - "${jenkins_host_port}:8080"
      - "${jenkins_agent_port}:50000"

    volumes:
      - ${jenkins_volume_name}:/var/jenkins_home
      - /var/run/docker.sock:/var/run/docker.sock

volumes:

  ${jenkins_volume_name}:
EOF

cd /opt/jenkins

docker compose up -d

aws eks update-kubeconfig \
  --region ${aws_region} \
  --name ${eks_cluster}

echo "Jenkins bootstrap completed"