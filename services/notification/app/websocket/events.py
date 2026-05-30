import asyncio
import json
import logging
import threading

from app.config import WEBSOCKET_HOST, WEBSOCKET_PORT
from app.websocket.socket_server import connected_clients, start_server

logger = logging.getLogger(__name__)


async def broadcast_event(message: str) -> None:
    stale = []
    for client in list(connected_clients):
        try:
            await client.send(message)
        except Exception:
            stale.append(client)
    for client in stale:
        connected_clients.discard(client)


def broadcast_event_sync(payload: dict) -> None:
    message = json.dumps(payload)
    try:
        loop = asyncio.get_running_loop()
        loop.create_task(broadcast_event(message))
    except RuntimeError:
        asyncio.run(broadcast_event(message))


def start_websocket_server() -> None:
    asyncio.run(start_server())


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
