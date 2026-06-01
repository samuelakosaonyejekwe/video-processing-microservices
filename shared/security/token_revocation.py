import logging
import os

logger = logging.getLogger(__name__)

_redis_client = None


def _redis_enabled() -> bool:
    return bool(os.getenv("REDIS_HOST", "").strip())


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


def _require_redis_in_production() -> bool:
    return os.getenv("APP_ENV", "development") == "production" and _redis_enabled()


def revoke_token(jti: str, ttl_seconds: int) -> None:
    # Coerce to int: Redis SETEX rejects float TTLs, and callers sometimes
    # derive the TTL from time.time() (a float). A non-int here would raise and
    # silently leave the token un-revoked.
    ttl_seconds = int(ttl_seconds)
    if not jti or ttl_seconds <= 0:
        return

    client = _get_redis()
    if client is None:
        if _require_redis_in_production():
            raise RuntimeError("Redis is required for token revocation in production")
        return

    try:
        client.setex(f"revoked:jti:{jti}", ttl_seconds, "1")
    except Exception as error:
        logger.warning("Failed to revoke token jti=%s: %s", jti, error)


def claim_refresh_token_use(jti: str, ttl_seconds: int) -> bool:
    """Atomically mark a refresh-token jti as used; True only for the first use.

    Closes the refresh-rotation replay race: two concurrent requests presenting
    the same refresh token can both pass verification, but only the one that
    wins this SET NX is allowed to rotate. Fails open (returns True) when Redis
    is not configured outside production.
    """
    ttl_seconds = int(ttl_seconds)
    if not jti or ttl_seconds <= 0:
        return True

    client = _get_redis()
    if client is None:
        if _require_redis_in_production():
            # Without the dedup store we cannot guarantee single-use; reject.
            return False
        return True

    try:
        return bool(client.set(f"refresh:used:{jti}", "1", nx=True, ex=ttl_seconds))
    except Exception as error:
        logger.warning("Failed to claim refresh token use jti=%s: %s", jti, error)
        return not _require_redis_in_production()


def is_token_revoked(jti: str) -> bool:
    if not jti:
        return False

    client = _get_redis()
    if client is None:
        if _require_redis_in_production():
            logger.error("Redis unavailable for token revocation check jti=%s", jti)
            return True
        return False

    try:
        return bool(client.exists(f"revoked:jti:{jti}"))
    except Exception as error:
        logger.warning("Failed to check token revocation jti=%s: %s", jti, error)
        return _require_redis_in_production()


def store_refresh_token(user_id: str, jti: str, ttl_seconds: int) -> None:
    if not user_id or not jti or ttl_seconds <= 0:
        return

    client = _get_redis()
    if client is None:
        return

    try:
        client.setex(f"refresh:{user_id}", ttl_seconds, jti)
    except Exception as error:
        logger.warning("Failed to store refresh token user_id=%s: %s", user_id, error)


def get_stored_refresh_jti(user_id: str) -> str | None:
    client = _get_redis()
    if client is None:
        return None

    try:
        return client.get(f"refresh:{user_id}")
    except Exception as error:
        logger.warning(
            "Failed to read refresh token user_id=%s: %s",
            user_id,
            error,
        )
        return None


def invalidate_refresh_token(user_id: str) -> None:
    client = _get_redis()
    if client is None:
        return

    try:
        client.delete(f"refresh:{user_id}")
    except Exception as error:
        logger.warning(
            "Failed to invalidate refresh token user_id=%s: %s",
            user_id,
            error,
        )
