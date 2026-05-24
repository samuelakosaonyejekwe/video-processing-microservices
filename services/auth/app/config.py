import os

POSTGRES_HOST = os.getenv(
    "POSTGRES_HOST",
    "postgresql"
)

POSTGRES_PORT = os.getenv(
    "POSTGRES_PORT",
    "5432"
)

POSTGRES_DB = os.getenv(
    "POSTGRES_DB",
    "video_converter_db"
)

POSTGRES_USER = os.getenv(
    "POSTGRES_USER",
    "postgres"
)

POSTGRES_PASSWORD = os.getenv(
    "POSTGRES_PASSWORD",
    "password123"
)

JWT_SECRET = os.getenv(
    "JWT_SECRET",
    "supersecretkey"
)

JWT_ALGORITHM = "HS256"

ACCESS_TOKEN_EXPIRE_MINUTES = 60