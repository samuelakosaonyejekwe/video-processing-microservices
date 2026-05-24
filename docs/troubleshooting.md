# Troubleshooting Guide

## Docker Issues

### Containers Not Starting

Check logs:

```bash
docker logs <container-id>
```

---

## Kubernetes Issues

### Pods Stuck in Pending

Check events:

```bash
kubectl describe pod <pod-name>
```

---

### CrashLoopBackOff

View pod logs:

```bash
kubectl logs <pod-name>
```

---

## RabbitMQ Issues

### Queue Not Created

Verify RabbitMQ:

```bash
kubectl get pods
```

---

## MongoDB Issues

### Authentication Failure

Verify credentials in:

- Kubernetes Secrets
- Helm values.yaml

---

## PostgreSQL Issues

### Database Connection Refused

Check PostgreSQL service:

```bash
kubectl get svc
```

---

## FFmpeg Issues

### Conversion Failure

Verify FFmpeg installation:

```bash
ffmpeg -version
```