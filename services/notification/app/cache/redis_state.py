import logging
import os

logger = logging.getLogger(__name__)


def _get_redis_client():
    host = os.getenv("REDIS_HOST", "").strip()
    if not host:
        return None

    try:
        import redis

        return redis.Redis(
            host=host,
            port=int(os.getenv("REDIS_PORT", "6379")),
            password=os.getenv("REDIS_PASSWORD") or None,
            decode_responses=True,
            socket_connect_timeout=2,
            socket_timeout=2,
        )
    except Exception as error:
        logger.warning("Redis client unavailable: %s", error)
        return None


def claim_job_notification(job_id: str, ttl_seconds: int = 604800) -> bool:
    """Return True when this job notification send can proceed."""
    if not job_id:
        return True

    client = _get_redis_client()
    if client is None:
        return True

    key = f"notification:job:{job_id}"
    try:
        return bool(client.set(key, "queued", nx=True, ex=ttl_seconds))
    except Exception as error:
        logger.warning("Notification claim failed job_id=%s: %s", job_id, error)
        return True


def mark_job_notification_sent(job_id: str, ttl_seconds: int = 604800) -> None:
    if not job_id:
        return

    client = _get_redis_client()
    if client is None:
        return

    key = f"notification:job:{job_id}"
    try:
        client.setex(key, ttl_seconds, "sent")
    except Exception as error:
        logger.warning(
            "Failed to mark notification sent job_id=%s: %s",
            job_id,
            error,
        )


def notification_already_sent(job_id: str) -> bool:
    if not job_id:
        return False

    client = _get_redis_client()
    if client is None:
        return False

    key = f"notification:job:{job_id}"
    try:
        return client.get(key) == "sent"
    except Exception as error:
        logger.warning(
            "Failed to read notification state job_id=%s: %s",
            job_id,
            error,
        )
        return False


def record_notification_delivery(recipient: str, correlation_id: str | None) -> None:
    client = _get_redis_client()
    if client is None:
        return

    key = f"notification:sent:{recipient}"
    try:
        client.setex(key, 86400, correlation_id or "sent")
    except Exception as error:
        logger.warning(
            "Failed to record notification delivery recipient=%s: %s",
            recipient,
            error,
        )
