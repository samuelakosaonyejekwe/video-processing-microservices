# Amazon EKS Setup Guide

## Install AWS CLI

```bash
sudo apt install awscli -y
```

---

## Configure AWS Credentials

```bash
aws configure
```

---

## Install kubectl

```bash
curl -LO "https://dl.k8s.io/release/$(curl -L -s \
https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
```

---

## Install eksctl

```bash
curl --silent --location \
"https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" \
| tar xz -C /tmp

sudo mv /tmp/eksctl /usr/local/bin
```

---

## Create Cluster

```bash
eksctl create cluster \
--name video-converter-cluster \
--region eu-west-2 \
--nodes 2 \
--managed
```

---

## Verify Cluster

```bash
kubectl get nodes
```