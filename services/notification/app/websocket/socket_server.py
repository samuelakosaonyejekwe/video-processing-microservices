import asyncio
import websockets
from app.config import WEBSOCKET_HOST, WEBSOCKET_PORT

connected_clients = set()


async def handler(websocket):

    connected_clients.add(websocket)

    try:

        async for message in websocket:

            print(f"Received message: {message}")

    finally:

        connected_clients.remove(websocket)


async def start_server():

    async with websockets.serve(handler, WEBSOCKET_HOST, WEBSOCKET_PORT):

        print(f"WebSocket server running on port {WEBSOCKET_PORT}")

        await asyncio.Future()


if __name__ == "__main__":

    asyncio.run(start_server())
