# Deployment Guide

## Local Deployment

### Start Docker Compose

```bash
docker-compose up -d
```

---

## Kubernetes Deployment

### Create Namespace

```bash
kubectl apply -f infrastructure/kubernetes/namespaces/
```

---

### Deploy Services

```bash
bash scripts/deploy-services.sh
```

---

### Deploy Helm Charts

```bash
bash scripts/deploy-helm.sh
```

---

## EKS Deployment

### Create EKS Cluster

```bash
bash scripts/deploy-eks.sh
```

---

### Configure kubectl

```bash
aws eks update-kubeconfig \
--region $AWS_REGION \
--name video-converter-cluster
```

---

## Verify Pods

```bash
kubectl get pods
```

---

## Verify Services

```bash
kubectl get svc
```