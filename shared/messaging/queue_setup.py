import os

import pika

VIDEO_DLX = "video.dlx"
VIDEO_DLQ_ROUTING_KEY = "failed"
NOTIFICATION_RETRY_TTL_MS = 30000
UPLOAD_RETRY_TTL_MS = 30000


def _queue(name_env: str, default: str) -> str:
    return os.getenv(name_env, default)


def declare_video_dlx(channel: pika.channel.Channel) -> None:
    channel.exchange_declare(
        exchange=VIDEO_DLX,
        exchange_type="direct",
        durable=True,
    )


def declare_pipeline_queues(
    channel: pika.channel.Channel,
    *,
    video_upload_queue: str | None = None,
    video_upload_retry_queue: str | None = None,
    video_upload_dlq: str | None = None,
    notification_queue: str | None = None,
    notification_retry_queue: str | None = None,
    gateway_events_queue: str | None = None,
    video_completed_queue: str | None = None,
    video_failed_queue: str | None = None,
    declare_gateway_events: bool = True,
    declare_video_failed: bool = False,
) -> None:
    video_upload_queue = video_upload_queue or _queue(
        "VIDEO_UPLOAD_QUEUE", "video-upload-queue"
    )
    video_upload_retry_queue = video_upload_retry_queue or _queue(
        "VIDEO_UPLOAD_RETRY_QUEUE", "video-upload-retry-queue"
    )
    video_upload_dlq = video_upload_dlq or _queue(
        "VIDEO_UPLOAD_DLQ", "video-upload-dlq"
    )
    notification_queue = notification_queue or _queue(
        "NOTIFICATION_QUEUE", "notification-queue"
    )
    notification_retry_queue = notification_retry_queue or _queue(
        "NOTIFICATION_RETRY_QUEUE", "notification-retry-queue"
    )
    gateway_events_queue = gateway_events_queue or _queue(
        "GATEWAY_EVENTS_QUEUE", "gateway-events-queue"
    )
    video_completed_queue = video_completed_queue or _queue(
        "VIDEO_COMPLETED_QUEUE", "video-completed-queue"
    )
    video_failed_queue = video_failed_queue or _queue(
        "VIDEO_FAILED_QUEUE", "video-failed-queue"
    )

    declare_video_dlx(channel)

    channel.queue_declare(
        queue=video_upload_queue,
        durable=True,
        arguments={
            "x-dead-letter-exchange": VIDEO_DLX,
            "x-dead-letter-routing-key": VIDEO_DLQ_ROUTING_KEY,
        },
    )
    channel.queue_declare(
        queue=video_upload_retry_queue,
        durable=True,
        arguments={
            "x-message-ttl": UPLOAD_RETRY_TTL_MS,
            "x-dead-letter-exchange": "",
            "x-dead-letter-routing-key": video_upload_queue,
        },
    )
    channel.queue_declare(queue=video_upload_dlq, durable=True)
    channel.queue_bind(
        exchange=VIDEO_DLX,
        queue=video_upload_dlq,
        routing_key=VIDEO_DLQ_ROUTING_KEY,
    )

    channel.queue_declare(queue=notification_queue, durable=True)
    channel.queue_declare(
        queue=notification_retry_queue,
        durable=True,
        arguments={
            "x-message-ttl": NOTIFICATION_RETRY_TTL_MS,
            "x-dead-letter-exchange": "",
            "x-dead-letter-routing-key": notification_queue,
        },
    )

    if declare_gateway_events and gateway_events_queue:
        channel.queue_declare(queue=gateway_events_queue, durable=True)

    if video_completed_queue:
        channel.queue_declare(queue=video_completed_queue, durable=True)

    if declare_video_failed and video_failed_queue:
        channel.queue_declare(queue=video_failed_queue, durable=True)
