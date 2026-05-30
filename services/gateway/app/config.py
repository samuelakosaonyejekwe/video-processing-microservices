import os

from app.shared_bootstrap import ensure_shared_path

ensure_shared_path()

from shared.constants import queues as shared_queues  # noqa: E402


def first_env(*names: str, default: str = "") -> str:

    for name in names:
        value = os.getenv(name)
        if value and value.strip():
            return value.strip()
    return default


AUTH_SERVICE_HOST = first_env("AUTH_SERVICE_HOST", "AUTH_HOST", default="auth-service")
AUTH_SERVICE_PORT = first_env("AUTH_SERVICE_PORT", "AUTH_PORT", default="8001")
CONVERTER_SERVICE_HOST = first_env(
    "CONVERTER_SERVICE_HOST", "CONVERTER_HOST", default="converter-service"
)
CONVERTER_SERVICE_PORT = first_env(
    "CONVERTER_SERVICE_PORT", "CONVERTER_PORT", default="8002"
)

JWT_AUTH_SERVICE_URL = first_env("JWT_AUTH_SERVICE_URL")
if not JWT_AUTH_SERVICE_URL:
    JWT_AUTH_SERVICE_URL = f"http://{AUTH_SERVICE_HOST}:{AUTH_SERVICE_PORT}"

CONVERTER_SERVICE_URL = first_env("CONVERTER_SERVICE_URL")
if not CONVERTER_SERVICE_URL:
    CONVERTER_SERVICE_URL = f"http://{CONVERTER_SERVICE_HOST}:{CONVERTER_SERVICE_PORT}"

APP_ENV = first_env("APP_ENV", "ENVIRONMENT", default="production")


def load_pem(env_name: str, file_path: str) -> str:

    if os.path.exists(file_path):
        with open(file_path, encoding="utf-8") as pem_file:
            file_value = pem_file.read().strip()
            if file_value:
                return file_value

    value = os.getenv(env_name)
    if value and value.strip():
        return value.strip()

    return ""


JWT_PUBLIC_KEY = load_pem("JWT_PUBLIC_KEY", "/run/secrets/jwt-public.pem")

JWT_ISSUER = first_env(
    "JWT_ISSUER", "JWT_TOKEN_ISSUER", default="video-converter-platform"
)

JWT_AUDIENCE = first_env(
    "JWT_AUDIENCE", "JWT_TOKEN_AUDIENCE", default="video-converter-users"
)

JWT_ALGORITHM = first_env("JWT_ALGORITHM", default="RS256").upper()

JWT_SECRET = first_env("JWT_SECRET")

SUPPORTED_JWT_ALGORITHMS = {
    "HS256",
    "HS384",
    "HS512",
    "RS256",
    "RS384",
    "RS512",
}

if JWT_ALGORITHM not in SUPPORTED_JWT_ALGORITHMS:
    raise RuntimeError(f"Unsupported JWT algorithm: {JWT_ALGORITHM}")

if JWT_ALGORITHM.startswith("RS") and not JWT_PUBLIC_KEY:
    if APP_ENV == "production":
        raise RuntimeError("JWT_PUBLIC_KEY is required for RS256-based authentication")

if JWT_ALGORITHM.startswith("HS") and not JWT_SECRET:
    if APP_ENV == "production":
        raise RuntimeError("JWT_SECRET is required for HS256-based authentication")

RATE_LIMIT_MAX_REQUESTS = int(first_env("RATE_LIMIT_MAX_REQUESTS", default="100"))

RATE_LIMIT_WINDOW_SECONDS = (
    int(first_env("RATE_LIMIT_WINDOW_MS", default="60000")) // 1000
) or int(first_env("RATE_LIMIT_WINDOW_SECONDS", default="60"))

_cors_raw = first_env("CORS_ALLOWED_ORIGINS", "FRONTEND_URL", default="*")
CORS_ALLOWED_ORIGINS = [
    origin.strip() for origin in _cors_raw.split(",") if origin.strip()
] or ["*"]

VIDEO_UPLOAD_QUEUE = first_env(
    "VIDEO_UPLOAD_QUEUE",
    "RABBITMQ_QUEUE",
    default=shared_queues.VIDEO_UPLOAD_QUEUE,
)
NOTIFICATION_QUEUE = first_env(
    "NOTIFICATION_QUEUE",
    "RABBITMQ_NOTIFICATION_QUEUE",
    default=shared_queues.NOTIFICATION_QUEUE,
)
GATEWAY_EVENTS_QUEUE = first_env(
    "GATEWAY_EVENTS_QUEUE",
    default=shared_queues.GATEWAY_EVENTS_QUEUE,
)
