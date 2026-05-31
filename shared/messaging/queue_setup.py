import os

import pika

VIDEO_DLX = "video.dlx"
VIDEO_DLQ_ROUTING_KEY = "failed"
NOTIFICATION_RETRY_TTL_MS = 30000
UPLOAD_RETRY_TTL_MS = 30000
VIDEO_COMPLETED_RETRY_TTL_MS = 30000


def _queue(name_env: str, default: str) -> str:
    return os.getenv(name_env, default)


def _open_channel(channel: pika.channel.Channel) -> pika.channel.Channel:
    connection = channel.connection
    if channel.is_open:
        return channel
    return connection.channel()


def _ensure_queue(
    channel: pika.channel.Channel,
    queue: str,
    *,
    durable: bool = True,
    arguments: dict | None = None,
) -> pika.channel.Channel:
    """Use passive declare when a legacy queue already exists."""
    try:
        channel.queue_declare(queue=queue, passive=True)
        return channel
    except pika.exceptions.ChannelClosedByBroker as exc:
        if exc.reply_code != 404:
            raise
        channel = _open_channel(channel)
        kwargs: dict = {"queue": queue, "durable": durable}
        if arguments:
            kwargs["arguments"] = arguments
        channel.queue_declare(**kwargs)
        return channel


def _ensure_queue_bind(
    channel: pika.channel.Channel,
    *,
    exchange: str,
    queue: str,
    routing_key: str,
) -> pika.channel.Channel:
    try:
        channel.queue_bind(exchange=exchange, queue=queue, routing_key=routing_key)
        return channel
    except pika.exceptions.ChannelClosedByBroker:
        return _open_channel(channel)


def declare_video_dlx(channel: pika.channel.Channel) -> pika.channel.Channel:
    """Ensure video.dlx exists without conflicting with legacy exchange metadata."""
    try:
        channel.exchange_declare(exchange=VIDEO_DLX, passive=True)
        return channel
    except pika.exceptions.ChannelClosedByBroker as exc:
        if exc.reply_code != 404:
            raise
        channel = _open_channel(channel)
        channel.exchange_declare(
            exchange=VIDEO_DLX,
            exchange_type="direct",
            durable=True,
        )
        return channel


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
    video_completed_retry_queue: str | None = None,
    video_failed_queue: str | None = None,
    declare_gateway_events: bool = True,
    declare_video_failed: bool = False,
    declare_upload_pipeline: bool = False,
    declare_notification_pipeline: bool = True,
    declare_video_completed_pipeline: bool = False,
) -> pika.channel.Channel:
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
    video_completed_retry_queue = video_completed_retry_queue or _queue(
        "VIDEO_COMPLETED_RETRY_QUEUE", "video-completed-retry-queue"
    )

    if declare_upload_pipeline:
        channel = declare_video_dlx(channel)

        channel = _ensure_queue(
            channel,
            video_upload_queue,
            arguments={
                "x-dead-letter-exchange": VIDEO_DLX,
                "x-dead-letter-routing-key": VIDEO_DLQ_ROUTING_KEY,
            },
        )
        channel = _ensure_queue(
            channel,
            video_upload_retry_queue,
            arguments={
                "x-message-ttl": UPLOAD_RETRY_TTL_MS,
                "x-dead-letter-exchange": "",
                "x-dead-letter-routing-key": video_upload_queue,
            },
        )
        channel = _ensure_queue(channel, video_upload_dlq)
        channel = _ensure_queue_bind(
            channel,
            exchange=VIDEO_DLX,
            queue=video_upload_dlq,
            routing_key=VIDEO_DLQ_ROUTING_KEY,
        )

    if declare_notification_pipeline:
        channel = _ensure_queue(channel, notification_queue)
        channel = _ensure_queue(
            channel,
            notification_retry_queue,
            arguments={
                "x-message-ttl": NOTIFICATION_RETRY_TTL_MS,
                "x-dead-letter-exchange": "",
                "x-dead-letter-routing-key": notification_queue,
            },
        )

    if declare_gateway_events and gateway_events_queue:
        channel = _ensure_queue(channel, gateway_events_queue)

    if declare_video_completed_pipeline and video_completed_queue:
        channel = _ensure_queue(channel, video_completed_queue)
        channel = _ensure_queue(
            channel,
            video_completed_retry_queue,
            arguments={
                "x-message-ttl": VIDEO_COMPLETED_RETRY_TTL_MS,
                "x-dead-letter-exchange": "",
                "x-dead-letter-routing-key": video_completed_queue,
            },
        )
    elif video_completed_queue:
        channel = _ensure_queue(channel, video_completed_queue)

    if declare_video_failed and video_failed_queue:
        channel = _ensure_queue(channel, video_failed_queue)

    return channel
