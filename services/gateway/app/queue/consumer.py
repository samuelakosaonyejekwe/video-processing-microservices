import json
import logging
import os
import threading
import time

import pika
from pika.exceptions import AMQPChannelError, AMQPConnectionError

from app.config import FRONTEND_URL
from app.database.job_repository import (
    claim_notification_send,
    get_job,
    mark_job_completed,
    mark_job_failed,
    mark_notification_sent,
    release_notification_claim,
)
from app.queue.producer import get_gateway_producer
from shared.email.renderer import render_email_template

logger = logging.getLogger(__name__)


class GatewayEventConsumer:

    def __init__(self):

        self.rabbitmq_host = os.getenv("RABBITMQ_HOST")

        self.rabbitmq_port = int(os.getenv("RABBITMQ_PORT", "5672"))

        self.rabbitmq_username = os.getenv("RABBITMQ_USERNAME")

        self.rabbitmq_password = os.getenv("RABBITMQ_PASSWORD")

        self.notification_queue = os.getenv("NOTIFICATION_QUEUE")

        self.gateway_events_queue = os.getenv("GATEWAY_EVENTS_QUEUE")

        self.video_completed_queue = os.getenv("VIDEO_COMPLETED_QUEUE")

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
            "VIDEO_COMPLETED_QUEUE",
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

                logger.info("Connecting gateway consumer to RabbitMQ...")

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

                if self.gateway_events_queue:
                    self.channel.queue_declare(
                        queue=self.gateway_events_queue, durable=True
                    )

                self.channel.queue_declare(
                    queue=self.video_completed_queue, durable=True
                )

                self.channel.queue_declare(queue=self.notification_queue, durable=True)

                self.channel.basic_qos(prefetch_count=1)

                logger.info("Gateway RabbitMQ consumer connected successfully")

                break

            except (AMQPConnectionError, AMQPChannelError) as error:

                logger.error("RabbitMQ connection failed: %s", str(error))

                logger.info("Retrying RabbitMQ connection in 5 seconds...")

                time.sleep(5)

    def reconnect(self):

        logger.warning("Reconnecting gateway RabbitMQ consumer...")

        self.close()

        self.connect()

    def _send_completion_email(self, job_id: str, payload: dict) -> None:
        job = claim_notification_send(job_id)
        if not job:
            return

        recipient = job.get("user_email")
        if not recipient:
            return

        filename = (
            payload.get("original_filename") or job.get("filename") or "your video"
        )
        frontend_url = FRONTEND_URL.rstrip("/")

        subject = "Your video conversion is ready"
        content = render_email_template(
            "success.html",
            filename=filename,
            frontend_url=frontend_url,
            job_id=job_id,
        )

        try:
            get_gateway_producer().publish_notification_event(
                recipient=recipient,
                subject=subject,
                content=content,
                job_id=job_id,
            )
            logger.info(
                "Completion notification queued job_id=%s recipient=%s",
                job_id,
                recipient,
            )
        except Exception as error:
            release_notification_claim(job_id)
            logger.error(
                "Failed to queue completion notification job_id=%s: %s",
                job_id,
                error,
            )

    def _send_failure_email(self, job_id: str, payload: dict) -> None:
        job = get_job(job_id)
        if not job:
            return

        recipient = job.get("user_email")
        if not recipient:
            return

        filename = (
            payload.get("original_filename") or job.get("filename") or "your video"
        )
        error_message = payload.get("error_message") or "Conversion failed"
        frontend_url = FRONTEND_URL.rstrip("/")

        subject = "Your video conversion failed"
        content = render_email_template(
            "failure.html",
            filename=filename,
            frontend_url=frontend_url,
            error_message=error_message,
        )

        try:
            get_gateway_producer().publish_notification_event(
                recipient=recipient,
                subject=subject,
                content=content,
                job_id=job_id,
            )
        except Exception as error:
            logger.error(
                "Failed to queue failure notification job_id=%s: %s",
                job_id,
                error,
            )

    def _handle_conversion_failed(self, payload: dict) -> None:
        job_id = payload.get("job_id")
        error_message = payload.get("error_message") or "Conversion failed"

        if not job_id:
            logger.warning("Conversion failed event missing job_id")
            return

        mark_job_failed(job_id, error_message)
        logger.warning(
            "Marked job failed job_id=%s error=%s",
            job_id,
            error_message,
        )
        self._send_failure_email(job_id, payload)

    def _handle_conversion_completed(self, payload: dict) -> None:
        job_id = payload.get("job_id")
        audio_s3_key = payload.get("audio_s3_key")

        if not job_id:
            logger.warning("Conversion completed event missing job_id")
            return

        if audio_s3_key:
            mark_job_completed(job_id, audio_s3_key)

        self._send_completion_email(job_id, payload)

    def process_message(self, ch, method, properties, body):

        try:

            message = json.loads(body)

            correlation_id = message.get("correlation_id")

            event_type = message.get("event_type")

            payload = message.get("payload", {})

            logger.info(
                "Gateway received event: " "event_type=%s correlation_id=%s",
                event_type,
                correlation_id,
            )

            if event_type == "video_conversion_completed":
                self._handle_conversion_completed(payload)

            elif event_type == "video_conversion_failed":
                self._handle_conversion_failed(payload)

            elif event_type == "notification_delivered":
                delivered_job_id = payload.get("job_id")
                if delivered_job_id:
                    mark_notification_sent(delivered_job_id)
                    logger.info(
                        "Notification delivery confirmed job_id=%s",
                        delivered_job_id,
                    )

            elif event_type == "notification_sent":
                logger.info("Processed notification event")

            else:

                logger.warning("Unknown event type received: %s", event_type)

            ch.basic_ack(delivery_tag=method.delivery_tag)

        except Exception as error:

            logger.error("Gateway consumer processing failed: %s", str(error))

            ch.basic_nack(delivery_tag=method.delivery_tag, requeue=False)

    def start(self):

        while not self._should_stop:

            try:

                logger.info(
                    "Gateway consumer waiting on queue=%s",
                    self.video_completed_queue,
                )

                self.channel.basic_consume(
                    queue=self.video_completed_queue,
                    on_message_callback=self.process_message,
                )

                self._ready_event.set()

                self.channel.start_consuming()

            except Exception as error:

                if self._should_stop:
                    break

                logger.error("Gateway consumer crashed: %s", str(error))

                time.sleep(5)

                self.reconnect()

    def stop(self) -> None:
        self._should_stop = True
        self._ready_event.clear()
        try:
            if self.channel and self.channel.is_open:
                self.channel.stop_consuming()
        except Exception as error:
            logger.warning("Gateway consumer stop_consuming failed: %s", error)
        self.close()

    def close(self):

        try:

            if self.channel:

                if self.channel.is_open:

                    self.channel.close()

            if self.connection:

                if self.connection.is_open:

                    self.connection.close()

            logger.info("Gateway RabbitMQ connection closed")

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
            _consumer_instance = GatewayEventConsumer()

            if _on_ready_callback:

                def _notify_ready():
                    if _consumer_instance._ready_event.wait(timeout=60):
                        _on_ready_callback()

                threading.Thread(
                    target=_notify_ready,
                    name="gateway-consumer-ready",
                    daemon=True,
                ).start()

            _consumer_instance.start()
        except Exception as error:
            logger.error(
                "Gateway consumer failed to start: %s",
                str(error),
            )

    _consumer_thread = threading.Thread(
        target=_run,
        name="gateway-consumer",
        daemon=False,
    )

    _consumer_thread.start()

    logger.info("Gateway consumer startup initiated")


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

    while True:
        time.sleep(3600)
