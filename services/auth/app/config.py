import os


def first_env(*names: str, default: str = "") -> str:

    for name in names:
        value = os.getenv(name)
        if value and value.strip():
            return value.strip()
    return default


APP_ENV = first_env("APP_ENV", "ENVIRONMENT", default="production")

APP_NAME = first_env("APP_NAME", default="auth-service")

APP_PORT = int(first_env("APP_PORT", "AUTH_SERVICE_PORT", "AUTH_PORT", default="8000"))

POSTGRES_HOST = first_env("POSTGRES_HOST", default="postgres")

POSTGRES_PORT = int(first_env("POSTGRES_PORT", default="5432"))

POSTGRES_DB = first_env("POSTGRES_DB", default="video_to_audio_converter")

POSTGRES_USER = first_env("POSTGRES_USER", default="postgres")

POSTGRES_PASSWORD = first_env("POSTGRES_PASSWORD")

POSTGRES_SSL_MODE = first_env("POSTGRES_SSL_MODE", default="prefer")


def load_pem(env_name: str, file_path: str) -> str:

    value = os.getenv(env_name)
    if value and value.strip():
        return value.strip()

    if os.path.exists(file_path):
        with open(file_path, encoding="utf-8") as pem_file:
            return pem_file.read().strip()

    return ""


JWT_PRIVATE_KEY = load_pem("JWT_PRIVATE_KEY", "/run/secrets/jwt-private.pem")
JWT_PUBLIC_KEY = load_pem("JWT_PUBLIC_KEY", "/run/secrets/jwt-public.pem")

JWT_ACTIVE_KID = first_env("JWT_ACTIVE_KID", default="default")

JWT_ISSUER = first_env(
    "JWT_ISSUER", "JWT_TOKEN_ISSUER", default="video-converter-platform"
)

JWT_AUDIENCE = first_env(
    "JWT_AUDIENCE", "JWT_TOKEN_AUDIENCE", default="video-converter-users"
)

JWT_ALGORITHM = first_env("JWT_ALGORITHM", default="RS256")

JWT_ACCESS_TOKEN_EXPIRES_MINUTES = int(
    first_env("JWT_ACCESS_TOKEN_EXPIRES_MINUTES", default="60")
)

_refresh_raw = first_env(
    "JWT_REFRESH_TOKEN_EXPIRES_DAYS",
    "JWT_REFRESH_TOKEN_EXPIRES_IN",
    default="7",
)
JWT_REFRESH_TOKEN_EXPIRES_DAYS = int(_refresh_raw.replace("d", "").strip())

_cors_raw = first_env("CORS_ALLOWED_ORIGINS", "FRONTEND_URL")
CORS_ALLOWED_ORIGINS = [
    origin.strip() for origin in _cors_raw.split(",") if origin.strip()
] or ["http://localhost:3000"]

DATABASE_URL = (
    f"postgresql://{POSTGRES_USER}:"
    f"{POSTGRES_PASSWORD}@"
    f"{POSTGRES_HOST}:"
    f"{POSTGRES_PORT}/"
    f"{POSTGRES_DB}"
    f"?sslmode={POSTGRES_SSL_MODE}"
)

required_env_vars = {
    "POSTGRES_HOST": POSTGRES_HOST,
    "POSTGRES_DB": POSTGRES_DB,
    "POSTGRES_USER": POSTGRES_USER,
    "POSTGRES_PASSWORD": POSTGRES_PASSWORD,
    "JWT_PRIVATE_KEY": JWT_PRIVATE_KEY,
    "JWT_PUBLIC_KEY": JWT_PUBLIC_KEY,
    "JWT_ISSUER": JWT_ISSUER,
    "JWT_AUDIENCE": JWT_AUDIENCE,
}

missing_vars = [key for key, value in required_env_vars.items() if not value]

if missing_vars and APP_ENV == "production":
    raise ValueError(
        "Missing required environment variables: " + ", ".join(missing_vars)
    )
