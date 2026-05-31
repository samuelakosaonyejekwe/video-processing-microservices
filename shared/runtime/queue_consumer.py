import os


def queue_consumer_enabled() -> bool:
    """Return True when this process should run an in-process RabbitMQ consumer."""
    explicit = os.getenv("ENABLE_QUEUE_CONSUMER", "").strip().lower()
    if explicit in ("true", "1", "yes"):
        return True
    if explicit in ("false", "0", "no"):
        return False

    app_env = os.getenv("APP_ENV", "production").strip().lower()
    if app_env in ("test", "production"):
        return False

    # Local docker-compose and dev environments keep the legacy combined API+consumer mode.
    return True
