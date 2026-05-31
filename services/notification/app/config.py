import os
from urllib.parse import quote_plus

from app.shared_bootstrap import ensure_shared_path

ensure_shared_path()

APP_ENV = os.getenv("APP_ENV", "production").strip()

APP_NAME = os.getenv("APP_NAME", "notification-service").strip()

APP_PORT = int(os.getenv("APP_PORT", "8003").strip())

SMTP_HOST = os.getenv("SMTP_HOST", "localhost")

SMTP_PORT = int(os.getenv("SMTP_PORT", "587").strip())

SMTP_USERNAME = (
    os.getenv("SMTP_USERNAME")
    or os.getenv("SMTP_EMAIL")
    or os.getenv("SMTP_FROM_EMAIL")
    or "noreply@localhost"
)

SMTP_PASSWORD = os.getenv("SMTP_PASSWORD", "")

SMTP_EMAIL = os.getenv("SMTP_EMAIL") or os.getenv("SMTP_USERNAME") or SMTP_USERNAME

SMTP_SECURE = os.getenv("SMTP_SECURE", "true").strip().lower() in (
    "true",
    "1",
    "yes",
)

SMTP_FROM_EMAIL = os.getenv("SMTP_FROM_EMAIL", SMTP_USERNAME).strip()

RABBITMQ_HOST = os.getenv("RABBITMQ_HOST", "rabbitmq")

RABBITMQ_PORT = int(os.getenv("RABBITMQ_PORT", "5672").strip())

RABBITMQ_USERNAME = os.getenv("RABBITMQ_USERNAME") or os.getenv(
    "RABBITMQ_DEFAULT_USER", "guest"
)

RABBITMQ_PASSWORD = os.getenv("RABBITMQ_PASSWORD") or os.getenv(
    "RABBITMQ_DEFAULT_PASS", "guest"
)

NOTIFICATION_QUEUE = os.getenv("NOTIFICATION_QUEUE", "notification-queue").strip()

WEBSOCKET_HOST = os.getenv("WEBSOCKET_HOST", "0.0.0.0").strip()

WEBSOCKET_PORT = int(os.getenv("WEBSOCKET_PORT", "8004").strip())

REDIS_HOST = os.getenv("REDIS_HOST", "redis").strip()

REDIS_PORT = int(os.getenv("REDIS_PORT", "6379").strip())

REDIS_PASSWORD = os.getenv("REDIS_PASSWORD", "")

RABBITMQ_URI = os.getenv("RABBITMQ_URI")

if not RABBITMQ_URI:
    encoded_user = quote_plus(RABBITMQ_USERNAME)
    encoded_password = quote_plus(RABBITMQ_PASSWORD)
    RABBITMQ_URI = (
        f"amqp://{encoded_user}:{encoded_password}" f"@{RABBITMQ_HOST}:{RABBITMQ_PORT}/"
    )

_cors_raw = os.getenv("CORS_ALLOWED_ORIGINS", "")
CORS_ALLOWED_ORIGINS = [
    origin.strip() for origin in _cors_raw.split(",") if origin.strip()
] or ["http://localhost:3000"]

if APP_ENV == "production":
    required = {
        "SMTP_HOST": SMTP_HOST,
        "SMTP_PASSWORD": SMTP_PASSWORD,
        "RABBITMQ_HOST": RABBITMQ_HOST,
    }
    missing = [k for k, v in required.items() if not v]
    if missing:
        raise ValueError(
            "Missing required environment variables: " + ", ".join(missing)
        )
