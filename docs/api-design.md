# API Design Documentation

## Gateway Service

Base URL:

```bash
http://localhost:8000
```

### Health Check

```http
GET /health
```

---

## Auth Service

Base URL:

```bash
http://localhost:8001
```

### Register User

```http
POST /auth/register
```

Payload:

```json
{
  "username": "testuser",
  "email": "example@gmail.com",
  "password": "password123"
}
```

---

### Login

```http
POST /auth/login
```

Payload:

```json
{
  "email": "admin@example.com",
  "password": "password123"
}
```

---

## Converter Service

Base URL:

```bash
http://localhost:8002
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
http://localhost:8003
```

### Health Check

```http
GET /health
```