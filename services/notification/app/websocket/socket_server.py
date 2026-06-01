"""WebSocket connection registry for this process.

Each notification API pod keeps its own in-memory registry. Cross-pod delivery
is handled by Redis pub/sub fanout (see redis_fanout.py): workers publish to
the ws:events channel and every API pod delivers to its local clients.
"""

import asyncio
import logging
import os

import websockets

from app.config import CORS_ALLOWED_ORIGINS, WEBSOCKET_HOST, WEBSOCKET_PORT
from shared.security.ws_auth import access_token_from_cookie_header, decode_access_token

logger = logging.getLogger(__name__)

connected_clients: dict[str, set] = {}

# Per-user connection cap and inbound frame-size limit to bound memory/CPU that
# an authenticated client can consume.
_MAX_CONNECTIONS_PER_USER = int(os.getenv("WS_MAX_CONNECTIONS_PER_USER", "5"))
_MAX_MESSAGE_BYTES = int(os.getenv("WS_MAX_MESSAGE_BYTES", str(64 * 1024)))


def _origin_allowed(origin: str | None) -> bool:
    # Browsers always send Origin on a WebSocket handshake; a cross-site forgery
    # attempt would carry a disallowed Origin. Missing Origin (non-browser
    # clients) is allowed because the cookie/JWT is still required.
    if not origin:
        return True
    if CORS_ALLOWED_ORIGINS == ["*"]:
        return True
    return origin in CORS_ALLOWED_ORIGINS


def register_client(user_key: str, websocket) -> None:
    connected_clients.setdefault(user_key, set()).add(websocket)


def unregister_client(user_key: str, websocket) -> None:
    clients = connected_clients.get(user_key)
    if not clients:
        return
    clients.discard(websocket)
    if not clients:
        connected_clients.pop(user_key, None)


async def handler(websocket):
    origin = websocket.request.headers.get("Origin")
    if not _origin_allowed(origin):
        await websocket.close(code=4403, reason="Forbidden origin")
        return

    cookie_header = websocket.request.headers.get("Cookie")
    token = access_token_from_cookie_header(cookie_header)
    payload = decode_access_token(token) if token else None
    if not payload:
        await websocket.close(code=4401, reason="Unauthorized")
        return

    user_key = str(payload.get("sub") or "")
    if not user_key:
        await websocket.close(code=4401, reason="Unauthorized")
        return

    if len(connected_clients.get(user_key, ())) >= _MAX_CONNECTIONS_PER_USER:
        await websocket.close(code=4429, reason="Too many connections")
        return

    register_client(user_key, websocket)

    try:
        async for message in websocket:
            # Inbound frames are not used; just bound their size and ignore them.
            logger.debug("WebSocket message from %s (%d bytes)", user_key, len(message))
    finally:
        unregister_client(user_key, websocket)


async def start_server():
    async with websockets.serve(
        handler,
        WEBSOCKET_HOST,
        WEBSOCKET_PORT,
        max_size=_MAX_MESSAGE_BYTES,
        ping_interval=20,
        ping_timeout=20,
    ):
        logger.info("WebSocket server running on %s:%s", WEBSOCKET_HOST, WEBSOCKET_PORT)
        await asyncio.Future()


if __name__ == "__main__":
    asyncio.run(start_server())
