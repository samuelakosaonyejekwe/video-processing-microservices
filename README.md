# Microservices Video Converter Platform

A production-grade, cloud-native video-to-audio conversion platform built on the DevSecOps discipline — every layer from developer laptop to AWS EKS is covered by automated security gates, immutable infrastructure, and observable pipelines.

---

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [Services](#services)
- [Technology Stack](#technology-stack)
- [Security Design](#security-design)
- [Infrastructure](#infrastructure)
- [CI/CD Pipelines](#cicd-pipelines)
- [Monitoring & Observability](#monitoring--observability)
- [Project Structure](#project-structure)
- [Prerequisites](#prerequisites)
- [Local Development](#local-development)
- [Running Tests](#running-tests)
- [Infrastructure Deployment](#infrastructure-deployment)
- [Platform Cost Management](#platform-cost-management)
- [Environment Variables](#environment-variables)
- [Author](#author)

---

## Architecture Overview

```
                        ┌─────────────────────────────────────┐
                        │            Client Browser            │
                        └──────────────┬──────────────────────┘
                                       │ HTTPS
                        ┌──────────────▼──────────────────────┐
                        │    AWS ALB  (ACM TLS termination)    │
                        └──────────────┬──────────────────────┘
                                       │
                        ┌──────────────▼──────────────────────┐
                        │        Gateway Service (8080)        │
                        │   Route  │  Auth  │  Rate-limit      │
                        └──┬───────┴───┬────┴─────────────────┘
                           │           │
          ┌────────────────▼┐    ┌─────▼───────────────┐
          │  Auth Service   │    │  Converter Service   │
          │  (8000)         │    │  (8002)  + ffmpeg    │
          │  PostgreSQL     │    │  S3 upload / output  │
          │  MongoDB        │    └──────────┬───────────┘
          └─────────────────┘               │ publish
                                     ┌──────▼──────────────┐
                                     │     RabbitMQ         │
                                     │  notification-queue  │
                                     │  retry-queue (TTL)   │
                                     │  DLQ                 │
                                     └──────┬───────────────┘
                                            │ consume
                                     ┌──────▼───────────────┐
                                     │  Notification Service │
                                     │  (8003)               │
                                     │  SMTP email + WS      │
                                     └───────────────────────┘

Infrastructure:  AWS EKS │ ECR │ S3 │ VPC │ IAM/IRSA │ Route 53 │ ACM
Persistence:     PostgreSQL │ MongoDB │ Redis │ MinIO (local)
```

**Request flow:** A client uploads a video through the Gateway. The Converter service stores the raw file in S3 and enqueues a conversion job to RabbitMQ. An ffmpeg worker processes the job, writes the MP3 to a second S3 bucket, and publishes a `notification_delivered` event. The Notification service consumes that event, sends an SMTP email and a WebSocket push to the originating user.

---

## Services

| Service | Port | Language | Purpose |
|---|---|---|---|
| **gateway** | 8080 | Python / FastAPI | Reverse proxy, JWT validation, rate limiting, CORS |
| **auth** | 8000 | Python / FastAPI | User registration, JWT issuance (RS256), refresh tokens, session cookies |
| **converter** | 8002 | Python / FastAPI + ffmpeg | Video upload to S3, async MP4 → MP3 conversion pipeline |
| **notification** | 8003 | Python / FastAPI | RabbitMQ consumer, SMTP delivery, WebSocket fan-out, idempotent deduplication |
| **frontend** | 3000 | Node / React | Single-page client application |

### Auth Service
- RS256 JWT access tokens with configurable expiry
- Refresh token rotation stored in MongoDB
- HTTP-only session cookies for browser clients
- Argon2 password hashing
- PostgreSQL as the primary user store

### Converter Service
- Streams uploaded files directly to S3 (`video-uploads` bucket)
- ffmpeg invoked as a subprocess — no temporary disk state
- Publishes conversion jobs to RabbitMQ with correlation IDs for end-to-end tracing
- KEDA `ScaledObject` autoscales converter pods based on RabbitMQ queue depth

### Notification Service
- Idempotent consumer using Redis-backed claim locks — duplicate messages are safely discarded
- Retry queue with TTL dead-letters messages back to the main queue (exponential backoff without polling)
- DLQ for messages that exhaust retries
- `EMAIL_ENABLED` flag (`false` in docker-compose) prevents SMTP connects during integration tests
- WebSocket broadcast targets users by JWT `sub` (user ID), not email

---

## Technology Stack

| Layer | Technology |
|---|---|
| **Runtime** | Python 3.12, FastAPI, Gunicorn/Uvicorn |
| **Containerisation** | Docker, Docker Compose |
| **Orchestration** | Kubernetes 1.29 on Amazon EKS |
| **IaC** | Terraform 1.8 (modular — VPC, EKS, ECR, IAM, Security Groups, Jenkins) |
| **CI/CD** | GitHub Actions, Jenkins |
| **Registry** | Amazon ECR (immutable tags) |
| **Messaging** | RabbitMQ 3 (management plugin, AMQP) |
| **Cache / State** | Redis |
| **Databases** | PostgreSQL 15, MongoDB 7 |
| **Object Storage** | Amazon S3 / MinIO (local) |
| **Media Processing** | ffmpeg |
| **Security Scanning** | Trivy 0.69, Gitleaks |
| **Autoscaling** | KEDA (event-driven), Kubernetes HPA, Cluster Autoscaler |
| **Ingress** | ingress-nginx, AWS ALB controller |
| **DNS / TLS** | Route 53, AWS ACM, ExternalDNS |
| **Monitoring** | Prometheus, Grafana (35-panel dashboard) |
| **Service Mesh / mTLS** | Kubernetes NetworkPolicy + mTLS (cert-manager) |

---

## Security Design

Security is enforced at every layer using automated gates — no manual approval steps are required to ship secure code.

### Shift-Left: Code & Secrets

| Control | Tooling |
|---|---|
| Secret detection on every push | Gitleaks (full git history scan) |
| Filesystem vulnerability scan | Trivy FS — CRITICAL/HIGH exit-code 1, SARIF → GitHub Security |
| Container image scan (all 5 services) | Trivy image matrix — runs in parallel after FS scan |
| IaC misconfiguration scan | Trivy config (first-party only, `--tf-exclude-downloaded-modules`) |
| Python code quality | Black, Flake8 enforced in CI |
| No hardcoded credentials | `.env.example` ships only key names; `.gitignore` excludes all secret files |

### Runtime: Kubernetes Pod Hardening

All workloads enforce the following `securityContext`:

```yaml
securityContext:
  readOnlyRootFilesystem: true
  runAsNonRoot: true
  allowPrivilegeEscalation: false
  capabilities:
    drop: [ALL]
```

RabbitMQ uses `emptyDir` volumes for `/etc/rabbitmq` and `/tmp` to satisfy `readOnlyRootFilesystem`.

### Network Security

- **Default-deny NetworkPolicy** — all pod-to-pod traffic is blocked by default
- Per-service allow policies permit only the exact ingress/egress paths required
- mTLS between services via cert-manager
- EKS control plane is private endpoint only (`cluster_endpoint_public_access = false`)
- VPC security groups scoped to `vpc_cidr` (no `0.0.0.0/0` egress)

### AWS IAM

- **IRSA (IAM Roles for Service Accounts)** — pods assume IAM roles via OIDC federation; no long-lived access keys on nodes
- **IMDSv2** enforced on all EC2 worker nodes (hop limit = 1)
- Least-privilege IAM policies per service (S3, ECR, CloudWatch)
- ECR repositories use **immutable image tags** — deployed images cannot be overwritten
- S3 buckets encrypted with customer-managed KMS keys (CMK)
- `map_public_ip_on_launch = false` on all subnets

### Secrets Management

| Secret type | Where stored |
|---|---|
| JWT RS256 key pair | GitHub Secrets → Kubernetes Secret |
| Database passwords | GitHub Secrets → Kubernetes Secret |
| SMTP credentials | GitHub Secrets → Kubernetes Secret |
| RabbitMQ credentials | GitHub Secrets → Kubernetes Secret |
| AWS credentials (CI) | GitHub Secrets only — never in code |

Terraform state is stored in S3 with DynamoDB locking — `terraform.tfvars` is generated at plan time and deleted at job end (`Cleanup Sensitive Files` step).

---

## Infrastructure

### Terraform Modules

```
infrastructure/terraform/
├── modules/
│   ├── ecr/              # Container registries (immutable tags)
│   ├── eks/              # Managed node groups, IRSA, private endpoint
│   ├── iam/              # IRSA roles, least-privilege policies
│   ├── jenkins/          # Jenkins EC2 instance
│   ├── security-groups/  # Scoped SG rules (vpc_cidr egress only)
│   └── vpc/              # VPC, subnets, NAT gateway, route tables
├── backend.tf            # S3 + DynamoDB remote state
├── iam-irsa.tf           # Pod-level IAM federation
└── variables.tf          # All inputs validated with condition blocks
```

### Kubernetes Namespaces

| Namespace | Workloads |
|---|---|
| `app` | gateway, auth, converter, notification, frontend |
| `database` | PostgreSQL, MongoDB |
| `messaging` | RabbitMQ, Redis |
| `monitoring` | Prometheus, Grafana, metrics-server |

### Autoscaling

- **KEDA `ScaledObject`** on the converter deployment — scales from 0 to N pods based on RabbitMQ queue depth via a `RabbitmqTriggerAuthentication` resource
- **Kubernetes HPA** on gateway and auth for CPU/memory-based scaling
- **Cluster Autoscaler** adjusts the EKS node group size automatically

---

## CI/CD Pipelines

### GitHub Actions Workflows

| Workflow | Trigger | Purpose |
|---|---|---|
| `ci.yml` — Global CI | push/PR to `main`, `develop` | Env validation, Black, Flake8, unit tests (per-service coverage), integration + e2e tests, YAML/Docker/Terraform/Helm/K8s manifest validation |
| `security.yml` — Security Pipeline | push/PR to `main` | Trivy FS scan, Trivy IaC scan, Trivy image scan (5-service matrix), Gitleaks secret scan |
| `terraform-eks.yml` — Infra Provisioning | push to `main` (tf paths) / `workflow_dispatch` | Bootstrap backend → generate tfvars → init → fmt → validate → plan → (on dispatch) apply → deploy services → production validation |
| `deploy-eks-services.yml` | `workflow_dispatch` | Deploy K8s manifests to existing cluster |
| `docker-build.yml` | `workflow_dispatch` | Build and push all service images to ECR |
| `shutdown-platform.yml` | `workflow_dispatch` | Soft (nodes=0 + Jenkins stop) or Full (destroy EKS + Jenkins + NAT) |
| `start-platform.yml` | `workflow_dispatch` | Full platform restore from any state — reruns Terraform, redeploys services |
| `start-eks.yml` / `stop-eks.yml` | `workflow_dispatch` | Scale EKS node group up/down |
| `start-jenkins.yml` / `stop-jenkins.yml` | `workflow_dispatch` | Start/stop Jenkins EC2 instance |
| `validate-k8s.yml` | push/PR | Parse and validate all K8s YAML manifests |

### CI Quality Gates (per push)

```
validate-environment  ──► python-quality ──► integration-tests
                          (black, flake8,     (docker compose --wait
                           unit tests,         full stack, pytest
                           coverage ≥ 30%)     e2e + integration)
                      ──► yaml-validation
                      ──► docker-validation
                      ──► terraform-validation
                      ──► helm-validation
                      ──► kubernetes-validation
```

All gates must pass before merge. The integration test job spins up the full compose stack with `--wait` (health-check aware) and runs `tests/integration` and `tests/e2e` against live services.

### Jenkins Pipeline

Jenkins runs on a dedicated EC2 instance (provisioned by Terraform) and handles the inner loop:

- Docker image builds (tagged with `BUILD_NUMBER`)
- ECR pushes per service
- Rolling deployment to EKS (`kubectl rollout`)
- Automated rollback on failed health checks
- `disableConcurrentBuilds()` prevents overlapping deploys

---

## Monitoring & Observability

### Prometheus

- `ServiceMonitor` resources per service (gateway, auth, converter, notification)
- Scrapes FastAPI `/metrics` endpoints exposed via `prometheus-fastapi-instrumentator`
- Metrics server installed for HPA resource metrics

### Grafana

- 35 live panels across a single consolidated dashboard
- Panels cover: HTTP request rate, error rate, P95/P99 latency, RabbitMQ queue depth, Redis memory, active WebSocket connections, pod restarts, CPU/memory per service
- Dashboard deployed as a Kubernetes `ConfigMap` via `scripts/deploy-grafana-dashboards.sh`
- Admin credentials managed via Kubernetes Secret

### Alerting

Prometheus alerting rules cover queue depth thresholds, pod crash-loop detection, and service unavailability.

---

## Project Structure

```
.
├── services/
│   ├── auth/                   # FastAPI auth service
│   ├── gateway/                # FastAPI API gateway
│   ├── converter/              # FastAPI + ffmpeg converter
│   ├── notification/           # FastAPI notification service
│   └── frontend/               # React SPA
│
├── infrastructure/
│   ├── terraform/
│   │   ├── modules/            # ecr, eks, iam, jenkins, security-groups, vpc
│   │   ├── scripts/            # bootstrap, init, plan, apply, configure-kubectl
│   │   └── *.tf                # Root module: main, iam-irsa, backend, variables, outputs
│   ├── kubernetes/
│   │   ├── auth/               # Deployment, Service, HPA
│   │   ├── converter/          # Deployment, Service, KEDA ScaledObject
│   │   ├── gateway/            # Deployment, Service, Ingress
│   │   ├── notification/       # Deployment, Service
│   │   ├── ingress-nginx/      # ingress-nginx Helm values
│   │   ├── keda/               # ScaledObject, TriggerAuthentication
│   │   ├── monitoring/         # Prometheus, Grafana, ServiceMonitors
│   │   ├── network-policies/   # Default-deny + per-service allow rules
│   │   ├── postgres/           # StatefulSet, PVC
│   │   ├── rabbitmq/           # StatefulSet, PVC, Service
│   │   ├── redis/              # Deployment, Service
│   │   ├── secrets/            # Secret manifest templates (values via CI)
│   │   ├── namespaces/         # app, database, messaging, monitoring
│   │   └── serviceaccounts/    # IRSA-annotated ServiceAccounts
│   └── helm/                   # Shared HPA chart, global values, NetworkPolicy
│
├── messaging/rabbitmq/         # RabbitMQ definitions, queues, config
│
├── security/trivy/
│   ├── trivy.yaml              # Trivy scanner config
│   ├── .trivyignore            # Accepted risk suppressions (documented)
│   └── reports/                # SARIF output (gitignored, uploaded to GitHub Security)
│
├── tests/
│   ├── e2e/                    # End-to-end flow tests (register → upload → convert → notify)
│   ├── integration/            # Service-level integration tests
│   ├── auth/                   # Auth-specific API tests
│   └── conftest.py             # Shared fixtures
│
├── scripts/                    # 60+ operational shell scripts
│   ├── deploy-eks.sh           # Deploy K8s manifests
│   ├── deploy-services.sh      # Apply service workloads
│   ├── deploy-monitoring.sh    # Prometheus + Grafana
│   ├── shutdown-platform.sh    # Soft / full platform shutdown
│   ├── start-platform.sh       # Full platform restore
│   ├── full-security-scan.sh   # Local Trivy fs + image + IaC scan
│   ├── run-integration-tests.sh # Compose-up + pytest
│   └── run-production-validation.sh # Post-deploy smoke test
│
├── .github/workflows/          # 20 GitHub Actions workflows
├── Jenkinsfile                 # Jenkins declarative pipeline
├── docker-compose.yml          # Full local stack (all services + dependencies)
├── Makefile                    # Developer convenience targets
└── .env.example                # All variable names with empty values (no secrets)
```

---

## Prerequisites

| Tool | Minimum version | Purpose |
|---|---|---|
| Docker + Docker Compose | 24 / v2 | Local development stack |
| Python | 3.12 | Service development and test runner |
| kubectl | 1.29 | Kubernetes cluster interaction |
| Helm | 3.14 | Chart rendering and deployment |
| Terraform | 1.8.5 | Infrastructure provisioning |
| AWS CLI | 2.x | AWS resource management |
| Trivy | 0.69 | Local security scans |
| Git | 2.x | Version control |

AWS credentials must be configured (`aws configure` or environment variables) with permissions for EKS, ECR, S3, VPC, IAM, and EC2.

---

## Local Development

### 1. Clone the repository

```bash
git clone https://github.com/samuelakosaonyejekwe/video-processing-microservices.git
cd video-processing-microservices
```

### 2. Configure environment

```bash
cp .env.example .env.compose.runtime
# Fill in required values — at minimum:
# POSTGRES_PASSWORD, MONGO_PASSWORD, RABBITMQ_PASSWORD,
# REDIS_PASSWORD, JWT_PRIVATE_KEY, JWT_PUBLIC_KEY
```

JWT keys can be generated locally:

```bash
openssl genrsa -out .compose-secrets/jwt-private.pem 2048
openssl rsa -in .compose-secrets/jwt-private.pem -pubout -out .compose-secrets/jwt-public.pem
```

### 3. Start the full stack

```bash
docker compose --env-file .env.compose.runtime up -d --build --wait
```

`--wait` honours health checks and dependency chains — the command only returns after every service is healthy. No sleep timers, no race conditions.

### 4. Verify services

| Endpoint | Service |
|---|---|
| `http://localhost:8080` | Gateway |
| `http://localhost:8000/docs` | Auth (Swagger UI) |
| `http://localhost:8002/docs` | Converter (Swagger UI) |
| `http://localhost:8003/docs` | Notification (Swagger UI) |
| `http://localhost:15672` | RabbitMQ management (log in with `${RABBITMQ_USERNAME}` / `${RABBITMQ_PASSWORD}`) |
| `http://localhost:9090` | Prometheus |
| `http://localhost:3000` | Grafana |

---

## Running Tests

### Unit tests (per service)

```bash
cd services/auth && pytest --cov=app --cov-report=term-missing
cd services/gateway && pytest --cov=app --cov-report=term-missing
cd services/converter && pytest --cov=app --cov-report=term-missing
cd services/notification && pytest --cov=app --cov-report=term-missing
```

### Full integration + e2e suite

```bash
bash scripts/run-integration-tests.sh
```

This script:
1. Starts the full docker compose stack with `--wait`
2. Runs the minio-init one-shot container
3. Waits for RabbitMQ AMQP to be ready
4. Runs `pytest tests/integration tests/e2e`
5. Runs a RabbitMQ queue health check
6. Tears down the stack on exit

### Security scan (local)

```bash
bash scripts/full-security-scan.sh

# Individual scans:
trivy fs . --severity CRITICAL,HIGH --exit-code 1
trivy config infrastructure/ --tf-exclude-downloaded-modules --severity CRITICAL,HIGH
trivy image <IMAGE_NAME> --severity CRITICAL,HIGH
```

---

## Infrastructure Deployment

### 1. Bootstrap Terraform backend (first time only)

```bash
bash infrastructure/terraform/scripts/bootstrap-terraform-backend.sh
```

Creates the S3 bucket and DynamoDB table used for remote state.

### 2. Generate tfvars and initialise

```bash
bash infrastructure/terraform/scripts/generate-terraform-tfvars.sh
bash infrastructure/terraform/scripts/terraform-init.sh
```

### 3. Plan and review

```bash
bash infrastructure/terraform/scripts/terraform-plan.sh
```

### 4. Apply (provisions VPC, EKS cluster, ECR, IAM, Jenkins EC2)

```bash
bash infrastructure/terraform/scripts/terraform-apply.sh
```

### 5. Deploy services to EKS

```bash
bash scripts/deploy-eks.sh
bash scripts/deploy-services.sh
```

Or trigger `terraform-eks.yml` via `workflow_dispatch` in GitHub Actions — it performs all steps end-to-end including production validation.

### 6. Verify deployment

```bash
bash scripts/verify-production-health.sh
```

---

## Platform Cost Management

Two GitHub Actions workflows allow the platform to be paused when not in use, significantly reducing AWS spend.

### Shutdown (`shutdown-platform.yml` → `workflow_dispatch`)

| Mode | What is stopped | Estimated remaining cost |
|---|---|---|
| `soft` | EKS nodes scaled to 0, Jenkins EC2 stopped | ~$116/month |
| `full` | EKS cluster destroyed, Jenkins terminated, NAT gateway removed | ~$10/month |

> **Warning:** `full` mode deletes EKS. Persistent database volumes may be lost depending on PVC retention policy. Use only when the platform is not needed for an extended period.

### Restore (`start-platform.yml` → `workflow_dispatch`)

Fully restores the platform from any shutdown state:
- Runs Terraform to recreate any destroyed resources (EKS, Jenkins, NAT)
- Reconfigures IRSA, ExternalDNS, ALB controller
- Redeploys all Kubernetes workloads
- Runs production validation smoke tests

---

## Environment Variables

All variables are documented in `.env.example`. Variables are grouped by function:

| Group | Key examples |
|---|---|
| **Application** | `APP_ENV`, `APP_PORT`, `CORS_ALLOWED_ORIGINS` |
| **AWS / EKS** | `AWS_REGION`, `EKS_CLUSTER_NAME`, `EKS_INSTANCE_TYPE`, `EKS_DESIRED_SIZE` |
| **Database** | `POSTGRES_PASSWORD`, `MONGO_PASSWORD`, `REDIS_PASSWORD` |
| **Messaging** | `RABBITMQ_PASSWORD`, `RABBITMQ_USERNAME`, `RABBITMQ_URI` |
| **JWT** | `JWT_PRIVATE_KEY`, `JWT_PUBLIC_KEY`, `JWT_SECRET`, `JWT_REFRESH_TOKEN_SECRET` |
| **SMTP** | `SMTP_HOST`, `SMTP_PORT`, `SMTP_EMAIL`, `SMTP_PASSWORD`, `EMAIL_ENABLED` |
| **Storage** | `AWS_S3_VIDEO_BUCKET`, `AWS_S3_AUDIO_BUCKET`, `AWS_S3_ENDPOINT_URL` |
| **Terraform** | `TF_STATE_BUCKET`, `TF_LOCK_TABLE` |
| **Observability** | `GRAFANA_ADMIN_PASSWORD`, `ENABLE_METRICS`, `ENABLE_TRACING` |

Sensitive values (passwords, keys) are stored exclusively in **GitHub Secrets** and injected into Kubernetes as **Secrets** at deploy time. They never appear in code, logs, or Terraform state in plaintext.

---

## Author

**Akosa Samuel Onyejekwe**  
Cloud · DevOps · Platform Engineering

GitHub: [samuelakosaonyejekwe](https://github.com/samuelakosaonyejekwe)

---

*Built to production-grade DevSecOps standards: shift-left security, immutable infrastructure, zero-trust networking, and fully automated delivery pipelines.*
