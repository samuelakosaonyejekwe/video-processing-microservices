import os
from urllib.parse import quote_plus

from app.shared_bootstrap import ensure_shared_path

ensure_shared_path()

from shared.constants import queues as shared_queues  # noqa: E402


def first_env(*names: str, default: str = "") -> str:

    for name in names:
        value = os.getenv(name)
        if value and value.strip():
            return value.strip()
    return default


APP_ENV = first_env("APP_ENV", "ENVIRONMENT", default="production")

APP_NAME = first_env("APP_NAME", default="converter-service")

APP_PORT = int(
    first_env("APP_PORT", "CONVERTER_SERVICE_PORT", "CONVERTER_PORT", default="8002")
)

AWS_REGION = first_env("AWS_REGION", default="eu-central-1")

S3_UPLOAD_BUCKET = first_env(
    "S3_UPLOAD_BUCKET",
    "AWS_S3_VIDEO_BUCKET",
    "AWS_S3_BUCKET",
    "S3_BUCKET_NAME",
    default="video-uploads",
)

S3_AUDIO_BUCKET = first_env(
    "S3_AUDIO_BUCKET", "AWS_S3_AUDIO_BUCKET", default=S3_UPLOAD_BUCKET
)

TEMP_PROCESSING_DIR = first_env(
    "TEMP_PROCESSING_DIR", "TEMP_STORAGE_PATH", default="/tmp/video-converter"
)

RABBITMQ_HOST = first_env("RABBITMQ_HOST", default="rabbitmq")

RABBITMQ_PORT = int(first_env("RABBITMQ_PORT", default="5672"))

RABBITMQ_USERNAME = first_env(
    "RABBITMQ_USERNAME", "RABBITMQ_DEFAULT_USER", default="guest"
)

RABBITMQ_PASSWORD = first_env(
    "RABBITMQ_PASSWORD", "RABBITMQ_DEFAULT_PASS", default="guest"
)

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

VIDEO_COMPLETED_QUEUE = first_env(
    "VIDEO_COMPLETED_QUEUE",
    default=shared_queues.VIDEO_COMPLETED_QUEUE,
)

VIDEO_FAILED_QUEUE = first_env(
    "VIDEO_FAILED_QUEUE",
    default=shared_queues.VIDEO_FAILED_QUEUE,
)

MONGO_HOST = first_env("MONGO_HOST", default="mongodb")

MONGO_PORT = int(first_env("MONGO_PORT", default="27017"))

MONGO_DATABASE = first_env("MONGO_DATABASE", default="video_converter")

MONGO_USERNAME = first_env("MONGO_USERNAME", default="mongo")

MONGO_PASSWORD = first_env("MONGO_PASSWORD", default="mongo")

_cors_raw = first_env("CORS_ALLOWED_ORIGINS", "FRONTEND_URL")
CORS_ALLOWED_ORIGINS = [
    origin.strip() for origin in _cors_raw.split(",") if origin.strip()
] or ["http://localhost:3000"]

encoded_mongo_password = quote_plus(MONGO_PASSWORD)

MONGO_URI = first_env("MONGO_URI") or (
    f"mongodb://{MONGO_USERNAME}:{encoded_mongo_password}"
    f"@{MONGO_HOST}:{MONGO_PORT}/{MONGO_DATABASE}"
    f"?authSource=admin"
)

MAX_CONVERSION_TIMEOUT_SECONDS = int(
    first_env("MAX_CONVERSION_TIMEOUT_SECONDS", default="90")
)

MAX_VIDEO_UPLOAD_SIZE_MB = int(first_env("MAX_VIDEO_UPLOAD_SIZE_MB", default="500"))


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

JWT_ALGORITHM = first_env("JWT_ALGORITHM", default="RS256")

if APP_ENV == "production" and CORS_ALLOWED_ORIGINS == ["http://localhost:3000"]:
    _frontend_origin = first_env("FRONTEND_URL")
    if _frontend_origin:
        CORS_ALLOWED_ORIGINS = [
            origin.strip() for origin in _frontend_origin.split(",") if origin.strip()
        ]
