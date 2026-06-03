"""Converter producer reconnect-and-retry behavior.

Mirrors the gateway fix: after a RabbitMQ restart the long-lived channel goes
stale, so the first publish raised and the event (e.g. the conversion-completed
notification) was dropped even though the connection was immediately
re-established. The producer must now reconnect and retry once.
"""

from unittest.mock import MagicMock

import pika
import pytest

from app.queue.producer import ConverterEventProducer

_ENV = {
    "RABBITMQ_HOST": "localhost",
    "RABBITMQ_PORT": "5672",
    "RABBITMQ_USERNAME": "user",
    "RABBITMQ_PASSWORD": "pass",
    "VIDEO_UPLOAD_QUEUE": "video-upload-queue",
    "NOTIFICATION_QUEUE": "notification-queue",
    "GATEWAY_EVENTS_QUEUE": "gateway-events-queue",
    "VIDEO_COMPLETED_QUEUE": "video-completed-queue",
    "VIDEO_FAILED_QUEUE": "video-failed-queue",
}


def _make_producer(monkeypatch):
    for key, value in _ENV.items():
        monkeypatch.setenv(key, value)
    monkeypatch.setattr(ConverterEventProducer, "connect", lambda self: None)
    return ConverterEventProducer()


def _open_channel():
    channel = MagicMock()
    channel.is_closed = False
    return channel


def test_completed_event_retries_once_after_stale_connection(monkeypatch):
    producer = _make_producer(monkeypatch)

    stale = _open_channel()
    stale.basic_publish.side_effect = pika.exceptions.StreamLostError("stale")
    fresh = _open_channel()

    producer.channel = stale
    monkeypatch.setattr(
        producer, "reconnect", lambda: setattr(producer, "channel", fresh)
    )

    correlation_id = producer.publish_conversion_completed_event(
        job_id="job-1",
        user_id="user-1",
        original_filename="v.mp4",
        audio_s3_key="outputs/audio/job-1.mp3",
        output_format="mp3",
    )

    assert isinstance(correlation_id, str) and correlation_id
    assert stale.basic_publish.call_count == 1
    assert fresh.basic_publish.call_count == 1


def test_completed_event_raises_when_all_attempts_fail(monkeypatch):
    producer = _make_producer(monkeypatch)

    def failing_channel():
        ch = _open_channel()
        ch.basic_publish.side_effect = pika.exceptions.StreamLostError("down")
        return ch

    producer.channel = failing_channel()
    monkeypatch.setattr(
        producer, "reconnect", lambda: setattr(producer, "channel", failing_channel())
    )

    with pytest.raises(pika.exceptions.AMQPError):
        producer.publish_conversion_completed_event(
            job_id="job-2",
            user_id="user-2",
            original_filename="v.mp4",
            audio_s3_key="outputs/audio/job-2.mp3",
            output_format="mp3",
        )


def test_failed_event_publishes_to_both_queues(monkeypatch):
    producer = _make_producer(monkeypatch)

    channel = _open_channel()
    producer.channel = channel

    correlation_id = producer.publish_conversion_failed_event(
        job_id="job-3",
        user_id="user-3",
        original_filename="v.mp4",
        error_message="boom",
    )

    assert isinstance(correlation_id, str) and correlation_id
    # one publish to the completed queue + one to the failed queue
    routing_keys = [
        call.kwargs["routing_key"] for call in channel.basic_publish.call_args_list
    ]
    assert "video-completed-queue" in routing_keys
    assert "video-failed-queue" in routing_keys
