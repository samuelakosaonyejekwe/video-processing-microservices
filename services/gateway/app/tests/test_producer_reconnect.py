"""Gateway producer reconnect-and-retry behavior.

Regression: after a RabbitMQ restart the gateway's long-lived channel goes
stale, so the first publish raised and the caller returned HTTP 503. The
producer must now reconnect and retry once so a single stale connection no
longer fails the request.
"""

from unittest.mock import MagicMock

import pika
import pytest

from app.queue.producer import GatewayEventProducer

_ENV = {
    "RABBITMQ_HOST": "localhost",
    "RABBITMQ_PORT": "5672",
    "RABBITMQ_USERNAME": "user",
    "RABBITMQ_PASSWORD": "pass",
    "VIDEO_UPLOAD_QUEUE": "video-upload-queue",
    "NOTIFICATION_QUEUE": "notification-queue",
    "GATEWAY_EVENTS_QUEUE": "gateway-events-queue",
    # validate_environment() requires this non-empty; the publish path hardcodes
    # exchange="" regardless, so the value is irrelevant to these tests.
    "RABBITMQ_EXCHANGE": "video-events",
}


def _make_producer(monkeypatch):
    for key, value in _ENV.items():
        monkeypatch.setenv(key, value)
    # Don't touch a real broker during construction.
    monkeypatch.setattr(GatewayEventProducer, "connect", lambda self: None)
    return GatewayEventProducer()


def _open_channel():
    channel = MagicMock()
    channel.is_closed = False
    return channel


def test_publish_retries_once_after_stale_connection(monkeypatch):
    producer = _make_producer(monkeypatch)

    stale = _open_channel()
    stale.basic_publish.side_effect = pika.exceptions.StreamLostError("stale")
    fresh = _open_channel()  # basic_publish succeeds (no side_effect)

    producer.channel = stale

    def fake_reconnect():
        producer.channel = fresh

    monkeypatch.setattr(producer, "reconnect", fake_reconnect)

    correlation_id = producer.publish_video_upload_event(
        job_id="job-1",
        user_id="user-1",
        filename="v.mp4",
        s3_key="uploads/videos/job-1/v.mp4",
        content_type="video/mp4",
    )

    assert isinstance(correlation_id, str) and correlation_id
    assert stale.basic_publish.call_count == 1  # first attempt failed
    assert fresh.basic_publish.call_count == 1  # retry on the reconnected channel


def test_publish_raises_when_all_attempts_fail(monkeypatch):
    producer = _make_producer(monkeypatch)

    def always_failing_channel():
        ch = _open_channel()
        ch.basic_publish.side_effect = pika.exceptions.StreamLostError("down")
        return ch

    producer.channel = always_failing_channel()
    monkeypatch.setattr(
        producer,
        "reconnect",
        lambda: setattr(producer, "channel", always_failing_channel()),
    )

    with pytest.raises(pika.exceptions.AMQPError):
        producer.publish_gateway_event("video_uploaded", {"job_id": "job-2"})


def test_publish_reconnects_when_channel_already_closed(monkeypatch):
    producer = _make_producer(monkeypatch)

    closed = _open_channel()
    closed.is_closed = True  # proactively detected as closed -> reconnect first
    fresh = _open_channel()

    producer.channel = closed
    reconnects = {"n": 0}

    def fake_reconnect():
        reconnects["n"] += 1
        producer.channel = fresh

    monkeypatch.setattr(producer, "reconnect", fake_reconnect)

    correlation_id = producer.publish_notification_event(
        recipient="a@example.com", subject="s", content="c"
    )

    assert isinstance(correlation_id, str) and correlation_id
    assert reconnects["n"] == 1
    assert closed.basic_publish.call_count == 0  # never published on the closed channel
    assert fresh.basic_publish.call_count == 1
