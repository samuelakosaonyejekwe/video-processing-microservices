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


def revoke_token(jti: str, ttl_seconds: int) -> None:
    if not jti or ttl_seconds <= 0:
        return

    client = _get_redis()
    if client is None:
        return

    try:
        client.setex(f"revoked:jti:{jti}", ttl_seconds, "1")
    except Exception as error:
        logger.warning("Failed to revoke token jti=%s: %s", jti, error)


def is_token_revoked(jti: str) -> bool:
    if not jti:
        return False

    client = _get_redis()
    if client is None:
        return False

    try:
        return bool(client.exists(f"revoked:jti:{jti}"))
    except Exception as error:
        logger.warning("Failed to check token revocation jti=%s: %s", jti, error)
        return False


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
