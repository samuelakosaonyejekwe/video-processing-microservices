# Microservices Video-to-Audio Converter Platform

A production-grade cloud-native microservices application for converting video files into audio using:

- Python FastAPI
- Docker
- Kubernetes
- Amazon EKS
- Helm
- RabbitMQ
- PostgreSQL
- MongoDB
- Jenkins
- GitHub Actions

---

# Architecture

Services included:

- Gateway Service
- Auth Service
- Converter Service
- Notification Service

Infrastructure includes:

- RabbitMQ
- PostgreSQL
- MongoDB
- Kubernetes
- Helm Charts
- CI/CD Pipelines

---

# Features

- JWT Authentication
- FFmpeg Video Conversion
- Queue-based Processing
- Real-time Notifications
- Dockerized Services
- Kubernetes Deployment
- Helm-based Infrastructure
- CI/CD Automation
- Scalable EKS Deployment

---

# Project Structure

```bash
microservices-video-to-converter-app/
```

---

# Local Development

## Start Services

```bash
docker-compose up -d
```

---

# Build Docker Images

```bash
bash scripts/build-images.sh
```

---

# Deploy to Kubernetes

```bash
bash scripts/deploy-services.sh
```

---

# Deploy Helm Charts

```bash
bash scripts/deploy-helm.sh
```

---

# Create EKS Cluster

```bash
bash scripts/deploy-eks.sh
```

---

# Run Tests

```bash
pytest tests/
```

---

# Monitoring

Supports:

- Prometheus
- Grafana
- Kubernetes Metrics Server

---

# CI/CD

Includes:

- Jenkins Pipeline
- GitHub Actions

---

# Technologies Used

- FastAPI
- Docker
- Kubernetes
- EKS
- Helm
- RabbitMQ
- MongoDB
- PostgreSQL
- FFmpeg
- Jenkins
- GitHub Actions

---

# License

MIT License