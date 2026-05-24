import os

SMTP_HOST = os.getenv(
    "SMTP_HOST",
    "smtp.example.com"
)

SMTP_PORT = int(
    os.getenv(
        "SMTP_PORT",
        587
    )
)

SMTP_USERNAME = os.getenv(
    "SMTP_USERNAME",
    "testuser@example.com"
)

SMTP_PASSWORD = os.getenv(
    "SMTP_PASSWORD",
    "password123"
)

RABBITMQ_HOST = os.getenv(
    "RABBITMQ_HOST",
    "rabbitmq"
)

RABBITMQ_PORT = int(
    os.getenv(
        "RABBITMQ_PORT",
        5672
    )
)

WEBSOCKET_HOST = os.getenv(
    "WEBSOCKET_HOST",
    "0.0.0.0"
)

WEBSOCKET_PORT = int(
    os.getenv(
        "WEBSOCKET_PORT",
        8765
    )
)