# Helm Deployment Guide

## Install Helm

```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

---

## Verify Helm

```bash
helm version
```

---

## Deploy MongoDB

```bash
helm install mongodb ./infrastructure/helm/mongodb
```

---

## Deploy PostgreSQL

```bash
helm install postgresql ./infrastructure/helm/postgresql
```

---

## Deploy RabbitMQ

```bash
helm install rabbitmq ./infrastructure/helm/rabbitmq
```

---

## List Helm Releases

```bash
helm list
```

---

## Uninstall Helm Release

```bash
helm uninstall mongodb
```