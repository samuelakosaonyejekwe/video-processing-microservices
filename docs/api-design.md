# API Design Documentation

## Gateway Service

Base URL:

```bash
http://localhost:${GATEWAY_PORT}
```

### Health Check

```http
GET /health
```

---

## Auth Service

Base URL:

```bash
http://localhost:${AUTH_SERVICE_PORT}
```

### Register User

```http
POST /auth/register
```

Payload:

```json
{
  "username": "${TEST_USERNAME}",
  "email": "${TEST_USER_EMAIL}",
  "password": "${TEST_USER_PASSWORD}"
}
```

### Environment Variables Required

```env
TEST_USERNAME=
TEST_USER_EMAIL=
TEST_USER_PASSWORD=
```

---

### Login

```http
POST /auth/login
```

Payload:

```json
{
  "email": "${ADMIN_EMAIL}",
  "password": "${ADMIN_PASSWORD}"
}
```

### Environment Variables Required

```env
ADMIN_EMAIL=
ADMIN_PASSWORD=
```

---

## Converter Service

Base URL:

```bash
http://localhost:${CONVERTER_SERVICE_PORT}
```

### Upload Video

```http
POST /convert
```

Form Data:

- file

---

## Notification Service

Base URL:

```bash
http://localhost:${NOTIFICATION_SERVICE_PORT}
```

### Health Check

```http
GET /health
```

---

# Required Environment Variables

```env
GATEWAY_PORT=8080

AUTH_SERVICE_PORT=8000

CONVERTER_SERVICE_PORT=8002

NOTIFICATION_SERVICE_PORT=8003

TEST_USERNAME=

TEST_USER_EMAIL=

TEST_USER_PASSWORD=

ADMIN_EMAIL=

ADMIN_PASSWORD=
```

---

# Production Security Notes

- Never hardcode usernames, emails, passwords, API keys, or tokens
- Never commit real credentials to GitHub
- Store secrets in:
  - GitHub Secrets
  - Kubernetes Secrets
  - Docker Secrets
  - AWS Secrets Manager
- Use `.env.example` for documentation only
- Add `.env` to `.gitignore`
- Rotate all exposed credentials immediately
- Avoid exposing internal infrastructure details in public documentation
```