import os
import time
import uuid
from datetime import datetime, timezone

import redis


def _redis_client():
    host = os.getenv("REDIS_HOST", "").strip()
    if not host:
        return None

    password = os.getenv("REDIS_PASSWORD") or None
    return redis.Redis(
        host=host,
        port=int(os.getenv("REDIS_PORT", "6379")),
        password=password,
        decode_responses=True,
        socket_connect_timeout=2,
        socket_timeout=2,
    )


def is_rate_limited(
    key: str,
    *,
    max_requests: int,
    window_seconds: int,
) -> bool:
    client = _redis_client()
    if client is None:
        return False

    now = int(time.time())
    bucket = f"rate:{key}:{now // window_seconds}"

    try:
        current = client.incr(bucket)
        if current == 1:
            client.expire(bucket, window_seconds + 1)
        return current > max_requests
    except redis.RedisError:
        return False


def rate_limit_key(client_ip: str, path: str) -> str:
    return f"{client_ip}:{path}"
