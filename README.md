# Microservices Video Converter Platform

Production-grade cloud-native video conversion platform built with:

- Python FastAPI microservices
- Docker
- Kubernetes
- Amazon EKS
- Terraform
- Jenkins
- GitHub Actions
- RabbitMQ
- Redis
- PostgreSQL
- Prometheus
- Grafana
- Trivy
- AWS IAM IRSA

---

# FEATURES

- Microservices architecture
- JWT authentication
- Video/audio conversion pipeline
- RabbitMQ asynchronous messaging
- Kubernetes autoscaling
- KEDA event-driven scaling
- Terraform Infrastructure as Code
- Jenkins + GitHub Actions CI/CD
- Trivy security scanning
- Prometheus/Grafana monitoring
- IRSA secure pod IAM
- IMDSv2 enforcement
- No hardcoded secrets

---

# PROJECT STRUCTURE

.
├── services/
│   ├── auth/
│   │   ├── app/
│   │   │   ├── database/
│   │   │   ├── jwt/
│   │   │   ├── middleware/
│   │   │   ├── models/
│   │   │   ├── queue/
│   │   │   ├── routes/
│   │   │   ├── schemas/
│   │   │   ├── services/
│   │   │   ├── tests/
│   │   │   ├── utils/
│   │   │   ├── config.py
│   │   │   └── main.py
│   │   ├── Dockerfile
│   │   ├── requirements.txt
│   │   └── pytest.ini
│   │
│   ├── gateway/
│   │   ├── app/
│   │   │   ├── middleware/
│   │   │   ├── routes/
│   │   │   ├── services/
│   │   │   ├── tests/
│   │   │   ├── config.py
│   │   │   └── main.py
│   │   ├── Dockerfile
│   │   └── requirements.txt
│   │
│   ├── converter/
│   │   ├── app/
│   │   │   ├── ffmpeg/
│   │   │   ├── queue/
│   │   │   ├── services/
│   │   │   ├── storage/
│   │   │   ├── tests/
│   │   │   ├── config.py
│   │   │   └── main.py
│   │   ├── Dockerfile
│   │   └── requirements.txt
│   │
│   ├── notification/
│   │   ├── app/
│   │   │   ├── email/
│   │   │   ├── queue/
│   │   │   ├── websocket/
│   │   │   ├── tests/
│   │   │   ├── config.py
│   │   │   └── main.py
│   │   ├── Dockerfile
│   │   └── requirements.txt
│   │
│   └── frontend/
│
├── infrastructure/
│   ├── terraform/
│   │   ├── modules/
│   │   │   ├── ecr/
│   │   │   ├── eks/
│   │   │   ├── iam/
│   │   │   ├── jenkins/
│   │   │   ├── security-groups/
│   │   │   └── vpc/
│   │   ├── eks.tf
│   │   ├── iam-irsa.tf
│   │   ├── main.tf
│   │   ├── outputs.tf
│   │   ├── providers.tf
│   │   ├── terraform.tfvars
│   │   └── variables.tf
│   │
│   ├── kubernetes/
│   │   ├── auth/
│   │   ├── converter/
│   │   ├── gateway/
│   │   ├── ingress-nginx/
│   │   ├── monitoring/
│   │   ├── namespaces/
│   │   ├── notification/
│   │   ├── postgres/
│   │   ├── rabbitmq/
│   │   ├── redis/
│   │   ├── secrets/
│   │   └── serviceaccounts/
│   │
│   └── helm/
│
├── messaging/
│   └── rabbitmq/
│       ├── definitions.json
│       ├── enabled_plugins
│       ├── queues.json
│       └── rabbitmq.conf
│
├── security/
│   └── trivy/
│       ├── trivy.yaml
│       ├── ignore.yaml
│       ├── reports/
│       └── templates/
│
├── scripts/
│   ├── deploy-eks.sh
│   ├── deploy-services.sh
│   ├── deploy-monitoring.sh
│   ├── full-security-scan.sh
│   ├── push-images.sh
│   └── discover-env-vars.sh
│
├── .github/
│   └── workflows/
│       ├── terraform-eks.yml
│       ├── security.yml
│       └── reusable-security.yml
│
├── Jenkinsfile
├── docker-compose.yml
├── Makefile
├── README.md
└── .env.example

---

# ARCHITECTURE

Client
   |
   v
Gateway Service
   |
   v
Authentication Service
   |
   v
RabbitMQ Queue
   |
   v
Converter Workers
   |
   v
Notification Service
   |
   v
Storage Layer

Infrastructure:
- AWS EKS
- AWS VPC
- AWS IAM
- AWS ECR
- AWS S3
- AWS CloudWatch

---

# SECURITY FEATURES

- IRSA enabled
- OIDC federation
- IMDSv2 enforced
- Trivy filesystem scanning
- Trivy image scanning
- Trivy IaC scanning
- Kubernetes Secrets
- Least-privilege IAM
- Secure service accounts
- No hardcoded credentials

---

# PREREQUISITES

Install:

- Docker
- kubectl
- Helm
- Terraform
- AWS CLI
- Python 3.11+
- Jenkins
- Git

---

# LOCAL DEVELOPMENT

Clone repository:

bash
git clone <REPOSITORY_URL>

cd microservices-video-to-converter-app

---

# START LOCAL STACK

bash
docker compose up --build

---

# TERRAFORM DEPLOYMENT

Initialize:

bash
terraform -chdir=infrastructure/terraform init

Validate:

bash
terraform -chdir=infrastructure/terraform validate

Plan:

bash
terraform -chdir=infrastructure/terraform plan

Apply:

bash
terraform -chdir=infrastructure/terraform apply

---

# DEPLOY TO EKS

bash
./scripts/deploy-eks.sh

---

# RUN SECURITY SCANS

Full security scan:

bash
./scripts/full-security-scan.sh

Filesystem scan:

bash
trivy fs .

Image scan:

bash
trivy image <IMAGE_NAME>

Terraform scan:

bash
trivy config infrastructure/

---

# MONITORING

Monitoring stack:
- Prometheus
- Grafana
- Kubernetes metrics
- FastAPI metrics
- Container metrics

---

# CI/CD

GitHub Actions handles:
- Terraform validation
- Security scanning
- Docker builds
- Kubernetes deployment

Jenkins handles:
- CI/CD orchestration
- Docker image builds
- ECR pushes
- Rollbacks
- Deployment automation

---

# IMPORTANT SECURITY NOTES

- Never hardcode secrets
- Use GitHub Secrets
- Use Kubernetes Secrets
- Use IRSA for pod permissions
- Rotate credentials regularly

---

# LICENSE

MIT License

---

# AUTHOR

Akosa Samuel Onyejekwe

Cloud / DevOps / Platform Engineering Project