import os


def record_notification_delivery(recipient: str, correlation_id: str | None) -> None:
    host = os.getenv("REDIS_HOST", "").strip()
    if not host:
        return

    try:
        import redis

        client = redis.Redis(
            host=host,
            port=int(os.getenv("REDIS_PORT", "6379")),
            password=os.getenv("REDIS_PASSWORD") or None,
            decode_responses=True,
            socket_connect_timeout=2,
            socket_timeout=2,
        )
        key = f"notification:sent:{recipient}"
        client.setex(key, 86400, correlation_id or "sent")
    except Exception:
        return
