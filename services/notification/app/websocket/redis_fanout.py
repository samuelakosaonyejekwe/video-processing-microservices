import asyncio
import json
import logging
import os
import time

from app.config import WS_PUBLISH_MAX_WAIT_SECONDS

logger = logging.getLogger(__name__)

WS_EVENTS_CHANNEL = "ws:events"
WS_PUBLISH_POLL_INTERVAL_SECONDS = 0.5

_fanout_subscriber_ready = False


def is_fanout_subscriber_ready() -> bool:
    return _fanout_subscriber_ready


def _set_fanout_subscriber_ready(ready: bool) -> None:
    global _fanout_subscriber_ready
    _fanout_subscriber_ready = ready


def _get_sync_redis_client():
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


def publish_ws_event(payload: dict) -> bool:
    """Publish a WebSocket event so every API pod can fan out locally."""
    client = _get_sync_redis_client()
    if client is None:
        return False

    message = json.dumps(payload)
    deadline = time.monotonic() + WS_PUBLISH_MAX_WAIT_SECONDS

    while True:
        try:
            subscribers = client.publish(WS_EVENTS_CHANNEL, message)
            if subscribers > 0:
                logger.debug(
                    "Published ws event type=%s recipient=%s subscribers=%s",
                    payload.get("type"),
                    payload.get("recipient"),
                    subscribers,
                )
                return True

            if time.monotonic() >= deadline:
                logger.warning(
                    "Published ws event type=%s recipient=%s but no subscribers "
                    "were listening after %ss",
                    payload.get("type"),
                    payload.get("recipient"),
                    WS_PUBLISH_MAX_WAIT_SECONDS,
                )
                return False

            logger.debug(
                "No ws fanout subscribers yet for type=%s recipient=%s; retrying",
                payload.get("type"),
                payload.get("recipient"),
            )
            time.sleep(WS_PUBLISH_POLL_INTERVAL_SECONDS)
        except Exception as error:
            logger.warning("Redis ws publish failed: %s", error)
            return False


async def redis_subscriber_loop(broadcast_fn) -> None:
    """Subscribe to Redis and deliver events to local WebSocket clients."""
    host = os.getenv("REDIS_HOST", "").strip()
    if not host:
        logger.info("REDIS_HOST not set; WebSocket fanout subscriber disabled")
        return

    try:
        import redis.asyncio as aioredis
    except ImportError:
        logger.warning(
            "redis package unavailable; WebSocket fanout subscriber disabled"
        )
        return

    password = os.getenv("REDIS_PASSWORD") or None
    retry_delay = 1.0
    max_retry_delay = 30.0

    while True:
        client = None
        pubsub = None
        try:
            client = aioredis.Redis(
                host=host,
                port=int(os.getenv("REDIS_PORT", "6379")),
                password=password,
                decode_responses=True,
            )
            pubsub = client.pubsub()
            await pubsub.subscribe(WS_EVENTS_CHANNEL)
            _set_fanout_subscriber_ready(True)
            logger.info(
                "WebSocket Redis fanout subscriber connected channel=%s",
                WS_EVENTS_CHANNEL,
            )
            retry_delay = 1.0

            async for message in pubsub.listen():
                if message["type"] != "message":
                    continue

                data = message.get("data")
                if not data:
                    continue

                try:
                    payload = json.loads(data)
                    recipient = payload.get("recipient")
                    await broadcast_fn(data, recipient=recipient)
                except Exception as error:
                    logger.warning("Failed to handle ws fanout message: %s", error)
        except asyncio.CancelledError:
            raise
        except Exception as error:
            _set_fanout_subscriber_ready(False)
            logger.warning(
                "WebSocket Redis fanout subscriber error: %s; retrying in %.1fs",
                error,
                retry_delay,
            )
            await asyncio.sleep(retry_delay)
            retry_delay = min(retry_delay * 2, max_retry_delay)
        finally:
            _set_fanout_subscriber_ready(False)
            if pubsub is not None:
                try:
                    await pubsub.unsubscribe(WS_EVENTS_CHANNEL)
                    await pubsub.aclose()
                except Exception:
                    pass
            if client is not None:
                try:
                    await client.aclose()
                except Exception:
                    pass
