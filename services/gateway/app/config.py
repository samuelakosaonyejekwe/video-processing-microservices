import os

AUTH_SERVICE_URL = os.getenv(
    "AUTH_SERVICE_URL",
    "http://auth-service:8001"
)

CONVERTER_SERVICE_URL = os.getenv(
    "CONVERTER_SERVICE_URL",
    "http://converter-service:8002"
)

JWT_SECRET = os.getenv(
    "JWT_SECRET",
    "supersecretkey"
)