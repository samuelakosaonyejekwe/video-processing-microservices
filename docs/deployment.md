# Deployment Guide

## Local Deployment

### Start Docker Compose

```bash
docker compose up --build
```

Verify the stack:

```bash
bash scripts/smoke-test-compose.sh
```

---

## Production Configuration Checklist

Before deploying to production, run:

```bash
bash scripts/validate-production-config.sh
```

Required for production:

- Strong secrets for Postgres, MongoDB, RabbitMQ, Redis, and Grafana
- Explicit `CORS_ALLOWED_ORIGINS` or `FRONTEND_URL`
- `POSTGRES_SSL_MODE=require` when connecting over the public internet
- TLS termination at the ingress/load balancer (ALB or nginx)

---

## Kubernetes Deployment

### Create Namespace

```bash
kubectl apply -f infrastructure/kubernetes/namespaces/
```

### Deploy Services

`scripts/deploy-services.sh` will:

1. Validate production configuration
2. Render and apply Kubernetes manifests
3. Run Postgres migrations (`RUN_POSTGRES_MIGRATIONS=true` by default)
4. Deploy API services and dedicated queue workers
5. Apply the converter temp-file cleanup CronJob

```bash
bash scripts/deploy-services.sh
```

### Readiness Probes

| Service | Liveness | Readiness |
|---------|----------|-----------|
| Gateway | `/health` | `/health/ready` (MongoDB) |
| Auth | `/health` | `/health/database` |
| Converter | `/health` | `/health/mongodb` |
| Notification | `/health` | `/health` |

Queue workers expose `/tmp/worker-ready` only after RabbitMQ consumption starts.

---

## Database Migrations

Run manually when needed:

```bash
bash scripts/run-postgres-migrations.sh
```

Migrations apply:

- `databases/postgresql/schema.sql`
- `databases/postgresql/migrations/*.sql`

Auth service disables runtime `create_all()` in production; migrations are the source of truth.

---

## Helm Deployment

```bash
bash scripts/deploy-helm.sh
```

RabbitMQ queue definitions live in `messaging/rabbitmq/definitions.json` and should stay in sync with service queue names.

---

## EKS Deployment

### Create EKS Cluster

```bash
bash scripts/deploy-eks.sh
```

### Configure kubectl

```bash
aws eks update-kubeconfig \
  --region "$AWS_REGION" \
  --name "$EKS_CLUSTER_NAME"
```

---

## Verify Deployment

```bash
kubectl get pods -n "$K8S_NAMESPACE"
kubectl get svc -n "$K8S_NAMESPACE"
bash scripts/run-production-validation.sh
```

---

## Rollback

```bash
kubectl rollout undo deployment/gateway-deployment -n "$K8S_NAMESPACE"
kubectl rollout undo deployment/auth-service -n "$K8S_NAMESPACE"
kubectl rollout undo deployment/converter-service -n "$K8S_NAMESPACE"
kubectl rollout undo deployment/notification-service -n "$K8S_NAMESPACE"
```
