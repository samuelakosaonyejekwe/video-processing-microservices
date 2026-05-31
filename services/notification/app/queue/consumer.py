import json
import logging
import os
import threading
import time

import pika

from pika.exceptions import AMQPConnectionError, AMQPChannelError

from app.cache.redis_state import (
    claim_job_notification,
    mark_job_notification_sent,
    notification_already_sent,
    record_notification_delivery,
    release_job_notification_claim,
)
from app.email.send_email import send_email
from app.websocket.events import broadcast_event_sync

from shared.events.schema import build_event

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")

logger = logging.getLogger(__name__)


class NotificationConsumer:

    def __init__(self):

        self.rabbitmq_host = os.getenv("RABBITMQ_HOST")

        self.rabbitmq_port = int(os.getenv("RABBITMQ_PORT", "5672"))

        self.rabbitmq_username = os.getenv("RABBITMQ_USERNAME")

        self.rabbitmq_password = os.getenv("RABBITMQ_PASSWORD")

        self.notification_queue = os.getenv("NOTIFICATION_QUEUE")

        self.retry_queue = os.getenv(
            "NOTIFICATION_RETRY_QUEUE", "notification-retry-queue"
        )

        self.notification_dlq = os.getenv("NOTIFICATION_DLQ", "notification-dlq")

        self.max_retry_attempts = int(os.getenv("MAX_NOTIFICATION_RETRIES", "3"))

        self.video_completed_queue = os.getenv(
            "VIDEO_COMPLETED_QUEUE", "video-completed-queue"
        )

        self.connection = None

        self.channel = None

        self._should_stop = False

        self._ready_event = threading.Event()

        self.validate_environment()

        self.connect()

    def validate_environment(self):

        required_environment_variables = [
            "RABBITMQ_HOST",
            "RABBITMQ_PORT",
            "RABBITMQ_USERNAME",
            "RABBITMQ_PASSWORD",
            "NOTIFICATION_QUEUE",
        ]

        missing_variables = []

        for variable in required_environment_variables:

            if not os.getenv(variable):

                missing_variables.append(variable)

        if missing_variables:

            raise ValueError(
                f"Missing required environment variables: " f"{missing_variables}"
            )

    def connect(self):

        while True:

            try:

                logger.info("Connecting to RabbitMQ...")

                credentials = pika.PlainCredentials(
                    username=self.rabbitmq_username, password=self.rabbitmq_password
                )

                parameters = pika.ConnectionParameters(
                    host=self.rabbitmq_host,
                    port=self.rabbitmq_port,
                    credentials=credentials,
                    heartbeat=600,
                    blocked_connection_timeout=300,
                    connection_attempts=5,
                    retry_delay=5,
                )

                self.connection = pika.BlockingConnection(parameters)

                self.channel = self.connection.channel()

                from shared.messaging.queue_setup import declare_pipeline_queues

                self.channel = declare_pipeline_queues(
                    self.channel,
                    notification_queue=self.notification_queue,
                    notification_retry_queue=self.retry_queue,
                    notification_dlq=self.notification_dlq,
                    video_completed_queue=self.video_completed_queue,
                    declare_gateway_events=False,
                )

                self.channel.basic_qos(prefetch_count=1)

                logger.info("RabbitMQ consumer connected successfully")

                break

            except (AMQPConnectionError, AMQPChannelError) as error:

                logger.error("RabbitMQ connection failed: %s", str(error))

                logger.info("Retrying connection in 5 seconds...")

                time.sleep(5)

    def reconnect(self):

        logger.warning("Reconnecting RabbitMQ consumer...")

        self.close()

        self.connect()

    def process_message(self, ch, method, properties, body):

        job_id = None
        correlation_id = None

        try:

            message = json.loads(body)

            payload = message.get("payload", {}) or {}
            retry_count = int(payload.get("retry_count", 0))

            recipient = payload.get("recipient")

            subject = payload.get("subject")

            content = payload.get("content")

            correlation_id = message.get("correlation_id")
            job_id = payload.get("job_id")

            if not recipient:

                raise ValueError("Missing recipient in notification payload")

            if job_id and notification_already_sent(job_id):
                logger.info(
                    "Skipping duplicate notification job_id=%s correlation_id=%s",
                    job_id,
                    correlation_id,
                )
                ch.basic_ack(delivery_tag=method.delivery_tag)
                return

            if job_id and not claim_job_notification(job_id):
                logger.info(
                    "Notification already in progress job_id=%s correlation_id=%s",
                    job_id,
                    correlation_id,
                )
                ch.basic_ack(delivery_tag=method.delivery_tag)
                return

            if not send_email(recipient, subject, content):
                raise RuntimeError(f"Email delivery failed for recipient={recipient}")

            if job_id:
                mark_job_notification_sent(job_id)

            record_notification_delivery(recipient, correlation_id)

            if job_id and self.video_completed_queue:
                try:
                    delivery_event = build_event(
                        "notification_delivered",
                        {"job_id": job_id, "recipient": recipient},
                        correlation_id,
                    )
                    self.channel.basic_publish(
                        exchange="",
                        routing_key=self.video_completed_queue,
                        body=json.dumps(delivery_event),
                        properties=pika.BasicProperties(
                            delivery_mode=2,
                            content_type="application/json",
                            correlation_id=correlation_id,
                        ),
                    )
                except Exception as publish_error:
                    logger.error(
                        "Delivery event publish failed job_id=%s: %s",
                        job_id,
                        publish_error,
                    )

            try:
                broadcast_event_sync(
                    {
                        "type": "notification_sent",
                        "recipient": recipient,
                        "correlation_id": correlation_id,
                        "subject": subject,
                    }
                )
            except Exception as broadcast_error:
                logger.warning(
                    "WebSocket broadcast failed correlation_id=%s: %s",
                    correlation_id,
                    broadcast_error,
                )

            logger.info(
                "Notification sent successfully " "to %s " "correlation_id=%s",
                recipient,
                correlation_id,
            )

            ch.basic_ack(delivery_tag=method.delivery_tag)

        except Exception as error:

            logger.error("Notification processing failed: %s", str(error))

            if job_id and notification_already_sent(job_id):
                ch.basic_ack(delivery_tag=method.delivery_tag)
                return

            if job_id:
                release_job_notification_claim(job_id)

            if retry_count < self.max_retry_attempts:
                retry_message = dict(message)
                retry_payload = dict(payload)
                retry_payload["retry_count"] = retry_count + 1
                retry_message["payload"] = retry_payload
                try:
                    self.channel.basic_publish(
                        exchange="",
                        routing_key=self.retry_queue,
                        body=json.dumps(retry_message),
                        properties=pika.BasicProperties(delivery_mode=2),
                    )
                    ch.basic_ack(delivery_tag=method.delivery_tag)
                    return
                except Exception as retry_error:
                    logger.error("Retry queue publish failed: %s", retry_error)

            try:
                self.channel.basic_publish(
                    exchange="",
                    routing_key=self.notification_dlq,
                    body=body,
                    properties=pika.BasicProperties(delivery_mode=2),
                )
                ch.basic_ack(delivery_tag=method.delivery_tag)
            except Exception as dlq_error:
                logger.error("Notification DLQ publish failed: %s", dlq_error)
                ch.basic_nack(delivery_tag=method.delivery_tag, requeue=False)

    def start(self):

        while not self._should_stop:

            try:

                logger.info("Waiting for notification events...")

                self.channel.basic_consume(
                    queue=self.notification_queue,
                    on_message_callback=self.process_message,
                )

                self.channel.basic_consume(
                    queue=self.retry_queue,
                    on_message_callback=self.process_message,
                )

                self._ready_event.set()

                self.channel.start_consuming()

            except Exception as error:

                if self._should_stop:
                    break

                logger.error("Consumer crashed: %s", str(error))

                time.sleep(5)

                self.reconnect()

    def stop(self) -> None:
        self._should_stop = True
        self._ready_event.clear()
        try:
            if self.channel and self.channel.is_open:
                self.channel.stop_consuming()
        except Exception as error:
            logger.warning("Notification consumer stop_consuming failed: %s", error)
        self.close()

    def close(self):

        try:

            if self.channel:

                if self.channel.is_open:

                    self.channel.close()

            if self.connection:

                if self.connection.is_open:

                    self.connection.close()

            logger.info("RabbitMQ consumer connection closed")

        except Exception as error:

            logger.error("Failed to close RabbitMQ connection: %s", str(error))


_consumer_instance = None
_consumer_thread = None
_on_ready_callback = None


def start_consumer(on_ready=None):

    import threading

    global _consumer_instance, _consumer_thread, _on_ready_callback

    _on_ready_callback = on_ready

    if _consumer_thread and _consumer_thread.is_alive():
        return

    def _run():

        global _consumer_instance

        try:
            _consumer_instance = NotificationConsumer()

            if _on_ready_callback:

                def _notify_ready():
                    if _consumer_instance._ready_event.wait(timeout=60):
                        _on_ready_callback()

                threading.Thread(
                    target=_notify_ready,
                    name="notification-consumer-ready",
                    daemon=True,
                ).start()

            _consumer_instance.start()
        except Exception as error:
            logger.error(
                "Notification consumer failed to start: %s",
                str(error),
            )

    _consumer_thread = threading.Thread(
        target=_run,
        name="notification-consumer",
        daemon=False,
    )

    _consumer_thread.start()

    logger.info("Notification consumer startup initiated")


def stop_consumer() -> None:
    global _consumer_instance, _consumer_thread

    if _consumer_instance is not None:
        _consumer_instance.stop()
        _consumer_instance = None

    if _consumer_thread and _consumer_thread.is_alive():
        _consumer_thread.join(timeout=15)
    _consumer_thread = None


if __name__ == "__main__":

    start_consumer()

    import time

    while True:
        time.sleep(3600)
