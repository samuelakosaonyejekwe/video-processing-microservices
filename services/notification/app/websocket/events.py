import asyncio
from app.websocket.socket_server import connected_clients


async def broadcast_event(message: str):

    if connected_clients:

        await asyncio.wait(
            [
                client.send(message)
                for client in connected_clients
            ]
        )