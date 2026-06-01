import json
from unittest.mock import AsyncMock, patch

import pytest

from app.websocket import events


@pytest.mark.asyncio
async def test_broadcast_event_sync_uses_redis_when_available():
    payload = {
        "type": "notification_sent",
        "recipient": "user@example.com",
        "correlation_id": "abc-123",
    }

    with patch(
        "app.websocket.events.publish_ws_event",
        return_value=True,
    ) as publish_mock:
        events.broadcast_event_sync(payload)

    publish_mock.assert_called_once_with(payload)


def test_broadcast_event_sync_falls_back_to_local_delivery():
    payload = {
        "type": "notification_sent",
        "recipient": "user@example.com",
    }
    message = json.dumps(payload)

    with (
        patch("app.websocket.events.publish_ws_event", return_value=False),
        patch(
            "app.websocket.events.broadcast_event",
            new_callable=AsyncMock,
        ) as broadcast_mock,
    ):
        events.broadcast_event_sync(payload)

    broadcast_mock.assert_awaited_once_with(message, recipient="user@example.com")
