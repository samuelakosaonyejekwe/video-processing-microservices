import asyncio
import json
import logging
import threading

from app.config import WEBSOCKET_HOST, WEBSOCKET_PORT
from app.websocket.redis_fanout import publish_ws_event, redis_subscriber_loop
from app.websocket.socket_server import connected_clients, start_server

logger = logging.getLogger(__name__)


async def broadcast_event(message: str, *, recipient: str | None = None) -> None:
    payload = json.loads(message)
    target = recipient or payload.get("recipient")
    stale = []

    if target:
        clients = list(connected_clients.get(str(target), set()))
    else:
        clients = [client for bucket in connected_clients.values() for client in bucket]

    for client in clients:
        try:
            await client.send(message)
        except Exception:
            stale.append((target, client))

    for user_key, client in stale:
        bucket = connected_clients.get(str(user_key) or "")
        if bucket:
            bucket.discard(client)
            if not bucket:
                connected_clients.pop(str(user_key), None)


def broadcast_event_sync(payload: dict) -> None:
    if publish_ws_event(payload):
        return

    message = json.dumps(payload)
    recipient = payload.get("recipient")
    try:
        loop = asyncio.get_running_loop()
        loop.create_task(broadcast_event(message, recipient=recipient))
    except RuntimeError:
        asyncio.run(broadcast_event(message, recipient=recipient))


async def _run_websocket_stack() -> None:
    await asyncio.gather(
        start_server(),
        redis_subscriber_loop(broadcast_event),
    )


def start_websocket_server() -> None:
    asyncio.run(_run_websocket_stack())


def start_websocket_background() -> None:
    thread = threading.Thread(
        target=start_websocket_server,
        name="notification-websocket",
        daemon=True,
    )
    thread.start()
    logger.info(
        "WebSocket server starting on %s:%s",
        WEBSOCKET_HOST,
        WEBSOCKET_PORT,
    )
