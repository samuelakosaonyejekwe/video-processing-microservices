import logging
import os
import time
import uuid

logger = logging.getLogger(__name__)

_redis_client = None


def rate_limit_key(client_id: str, path: str) -> str:
    return f"{client_id}:{path}"


def _redis_enabled() -> bool:
    return bool(os.getenv("REDIS_HOST", "").strip())


def _fail_closed() -> bool:
    explicit = os.getenv("RATE_LIMIT_FAIL_CLOSED", "").strip().lower()
    if explicit in ("1", "true", "yes"):
        return True
    if explicit in ("0", "false", "no"):
        return False
    return os.getenv("APP_ENV") == "production" and _redis_enabled()


def _get_redis():
    global _redis_client

    if _redis_client is not None:
        return _redis_client

    if not _redis_enabled():
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


def is_rate_limited(
    key: str,
    *,
    max_requests: int,
    window_seconds: int,
) -> bool:
    """Return True when the key exceeds the allowed request count."""
    client = _get_redis()
    if client is None:
        if _redis_enabled() and _fail_closed():
            logger.warning(
                "Rate limit fail-closed: Redis client unavailable key=%s",
                key,
            )
            return True
        return False

    now = time.time()
    redis_key = f"rate:{key}"

    try:
        pipeline = client.pipeline()
        pipeline.zremrangebyscore(redis_key, 0, now - window_seconds)
        # Unique member per request (score = timestamp). Using str(now) as the
        # member collapses requests that share a timestamp into one ZSET entry,
        # which undercounts bursts and lets the limit be bypassed.
        member = f"{now}:{uuid.uuid4().hex}"
        pipeline.zadd(redis_key, {member: now})
        pipeline.zcard(redis_key)
        pipeline.expire(redis_key, window_seconds + 1)
        _, _, count, _ = pipeline.execute()
        return int(count) > max_requests
    except Exception as error:
        logger.warning("Redis rate limit check failed key=%s: %s", key, error)
        if _fail_closed():
            return True
        return False
