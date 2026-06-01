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


class IdempotencyUnavailableError(RuntimeError):
    """Raised when idempotency is required but the backing store is unavailable."""


def _idempotency_required() -> bool:
    explicit = os.getenv("IDEMPOTENCY_REQUIRED", "").strip().lower()
    if explicit in ("1", "true", "yes"):
        return True
    if explicit in ("0", "false", "no"):
        return False
    # Fail closed in production when Redis is the configured dedup backend, so a
    # Redis outage requeues messages instead of silently allowing duplicates.
    return os.getenv("APP_ENV") == "production" and bool(
        os.getenv("REDIS_HOST", "").strip()
    )


def _on_unavailable(key: str, reason: str) -> bool:
    """Decide what to do when the dedup store cannot answer.

    Fail-open (return True) silently allows duplicate processing, so when
    IDEMPOTENCY_REQUIRED is set we fail closed by raising — the caller should
    leave the message unacknowledged so it is redelivered once Redis recovers,
    rather than processing it without a duplicate guarantee.
    """
    if _idempotency_required():
        raise IdempotencyUnavailableError(
            f"Idempotency store unavailable for key={key}: {reason}"
        )
    logger.warning(
        "Idempotency store unavailable key=%s (%s); allowing without dedup", key, reason
    )
    return True


def claim_once(key: str, ttl_seconds: int = 3600) -> bool:
    """Return True when this is the first claim for key within ttl."""
    client = _get_redis()
    if client is None:
        return _on_unavailable(key, "redis not configured")

    try:
        return bool(client.set(f"idempotency:{key}", "1", nx=True, ex=ttl_seconds))
    except Exception as error:
        return _on_unavailable(key, str(error))


def release_claim(key: str) -> None:
    """Release a previously-acquired claim so the work can be retried.

    Used when processing fails after claiming: without releasing, the 24h claim
    would cause every redelivery to be treated as a duplicate and dropped.
    """
    client = _get_redis()
    if client is None:
        return
    try:
        client.delete(f"idempotency:{key}")
    except Exception as error:
        logger.warning("Failed to release idempotency claim key=%s: %s", key, error)
