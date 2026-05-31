import logging
import os

logger = logging.getLogger(__name__)

_redis_client = None


def _get_redis():
    global _redis_client

    if _redis_client is not None:
        return _redis_client

    if not os.getenv("REDIS_HOST", "").strip():
        return None

    import redis

    password = os.getenv("REDIS_PASSWORD") or None
    _redis_client = redis.Redis(
        host=os.getenv("REDIS_HOST", "localhost"),
        port=int(os.getenv("REDIS_PORT", "6379")),
        password=password,
        decode_responses=True,
        socket_connect_timeout=2,
        socket_timeout=2,
    )
    return _redis_client


def claim_once(key: str, ttl_seconds: int = 3600) -> bool:
    """Return True when this is the first claim for key within ttl."""
    client = _get_redis()
    if client is None:
        return True

    try:
        return bool(client.set(f"idempotency:{key}", "1", nx=True, ex=ttl_seconds))
    except Exception as error:
        logger.warning("Idempotency claim failed key=%s: %s", key, error)
        return True
