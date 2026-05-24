import os

RABBITMQ_HOST = os.getenv(
    "RABBITMQ_HOST",
    "rabbitmq"
)

RABBITMQ_PORT = int(
    os.getenv("RABBITMQ_PORT", 5672)
)

MONGODB_URI = os.getenv(
    "MONGODB_URI",
    "mongodb://admin:password123@mongodb:27017"
)

UPLOAD_FOLDER = os.getenv(
    "UPLOAD_FOLDER",
    "uploads"
)

OUTPUT_FOLDER = os.getenv(
    "OUTPUT_FOLDER",
    "output"
)