import asyncio
import logging

import websockets

from app.config import WEBSOCKET_HOST, WEBSOCKET_PORT
from shared.security.ws_auth import access_token_from_cookie_header, decode_access_token

logger = logging.getLogger(__name__)

connected_clients: dict[str, set] = {}


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
    cookie_header = websocket.request.headers.get("Cookie")
    token = access_token_from_cookie_header(cookie_header)
    payload = decode_access_token(token) if token else None
    if not payload:
        await websocket.close(code=4401, reason="Unauthorized")
        return

    user_key = str(payload.get("email") or payload.get("sub") or "")
    if not user_key:
        await websocket.close(code=4401, reason="Unauthorized")
        return

    register_client(user_key, websocket)

    try:
        async for message in websocket:
            logger.debug("WebSocket message from %s: %s", user_key, message)
    finally:
        unregister_client(user_key, websocket)


async def start_server():
    async with websockets.serve(handler, WEBSOCKET_HOST, WEBSOCKET_PORT):
        logger.info("WebSocket server running on %s:%s", WEBSOCKET_HOST, WEBSOCKET_PORT)
        await asyncio.Future()


if __name__ == "__main__":
    asyncio.run(start_server())
