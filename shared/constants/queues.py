import os

VIDEO_UPLOAD_QUEUE = os.getenv("VIDEO_UPLOAD_QUEUE", "video-upload-queue")

VIDEO_UPLOAD_RETRY_QUEUE = os.getenv(
    "VIDEO_UPLOAD_RETRY_QUEUE", "video-upload-retry-queue"
)

VIDEO_UPLOAD_DLQ = os.getenv("VIDEO_UPLOAD_DLQ", "video-upload-dlq")

NOTIFICATION_QUEUE = os.getenv("NOTIFICATION_QUEUE", "notification-queue")

GATEWAY_EVENTS_QUEUE = os.getenv("GATEWAY_EVENTS_QUEUE", "gateway-events-queue")

EMAIL_QUEUE = os.getenv("EMAIL_QUEUE", "email-queue")

VIDEO_COMPLETED_QUEUE = os.getenv("VIDEO_COMPLETED_QUEUE", "video-completed-queue")

VIDEO_FAILED_QUEUE = os.getenv("VIDEO_FAILED_QUEUE", "video-failed-queue")
