import json
from unittest.mock import MagicMock, patch

from app.websocket.redis_fanout import WS_EVENTS_CHANNEL, publish_ws_event


def test_publish_ws_event_returns_false_without_redis_host(monkeypatch):
    monkeypatch.delenv("REDIS_HOST", raising=False)

    assert (
        publish_ws_event({"type": "notification_sent", "recipient": "a@b.com"}) is False
    )


def test_publish_ws_event_publishes_json_payload(monkeypatch):
    monkeypatch.setenv("REDIS_HOST", "redis")
    monkeypatch.setenv("REDIS_PORT", "6379")

    mock_client = MagicMock()
    mock_client.publish.return_value = 2

    with patch(
        "app.websocket.redis_fanout._get_sync_redis_client",
        return_value=mock_client,
    ):
        payload = {
            "type": "notification_sent",
            "recipient": "user@example.com",
            "correlation_id": "abc-123",
        }
        assert publish_ws_event(payload) is True

    mock_client.publish.assert_called_once_with(
        WS_EVENTS_CHANNEL,
        json.dumps(payload),
    )


def test_publish_ws_event_returns_false_when_no_subscribers(monkeypatch):
    monkeypatch.setenv("REDIS_HOST", "redis")

    mock_client = MagicMock()
    mock_client.publish.return_value = 0

    with (
        patch(
            "app.websocket.redis_fanout._get_sync_redis_client",
            return_value=mock_client,
        ),
        patch("app.websocket.redis_fanout.WS_PUBLISH_MAX_WAIT_SECONDS", 0),
    ):
        assert publish_ws_event({"type": "notification_sent"}) is False


def test_publish_ws_event_retries_until_subscribers_available(monkeypatch):
    monkeypatch.setenv("REDIS_HOST", "redis")

    mock_client = MagicMock()
    mock_client.publish.side_effect = [0, 0, 1]

    with (
        patch(
            "app.websocket.redis_fanout._get_sync_redis_client",
            return_value=mock_client,
        ),
        patch("app.websocket.redis_fanout.WS_PUBLISH_MAX_WAIT_SECONDS", 5),
        patch("app.websocket.redis_fanout.time.sleep") as sleep_mock,
    ):
        assert publish_ws_event({"type": "notification_sent"}) is True

    assert mock_client.publish.call_count == 3
    assert sleep_mock.call_count == 2


def test_publish_ws_event_returns_false_on_redis_error(monkeypatch):
    monkeypatch.setenv("REDIS_HOST", "redis")

    mock_client = MagicMock()
    mock_client.publish.side_effect = RuntimeError("connection refused")

    with (
        patch(
            "app.websocket.redis_fanout._get_sync_redis_client",
            return_value=mock_client,
        ),
        patch("app.websocket.redis_fanout.WS_PUBLISH_MAX_WAIT_SECONDS", 0),
    ):
        assert publish_ws_event({"type": "notification_sent"}) is False
