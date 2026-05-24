# Video-to-Audio Converter Microservices Architecture

## Overview

This project is a cloud-native microservices-based video-to-audio conversion platform built using:

- Python FastAPI
- Docker
- Kubernetes
- Amazon EKS
- Helm
- RabbitMQ
- MongoDB
- PostgreSQL

---

## Services

### Gateway Service

Acts as the API gateway for incoming client requests.

Responsibilities:

- Request routing
- Authentication forwarding
- Health checks
- API aggregation

---

### Auth Service

Handles:

- User registration
- Login
- JWT token generation
- Token validation

Uses PostgreSQL.

---

### Converter Service

Handles:

- Video uploads
- FFmpeg conversion
- Queue publishing
- Audio generation

Uses:

- RabbitMQ
- MongoDB
- FFmpeg

---

### Notification Service

Handles:

- Email notifications
- WebSocket updates
- Queue consumption

Uses RabbitMQ.

---

## Infrastructure Components

### RabbitMQ

Provides asynchronous communication between services.

Queues:

- video_conversion
- notifications

---

### MongoDB

Stores:

- media metadata
- conversion records
- logs

---

### PostgreSQL

Stores:

- users
- authentication data
- relational records

---

## Deployment Stack

- Docker containers
- Kubernetes manifests
- Helm charts
- Amazon EKS

---

## CI/CD

CI/CD implemented using:

- GitHub Actions
- Jenkins

---

## Monitoring

Monitoring stack includes:

- Prometheus
- Grafana
- Metrics Server