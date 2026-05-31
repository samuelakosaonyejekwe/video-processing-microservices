import json
import logging
import os
import time

import pika
from pika.exceptions import AMQPChannelError, AMQPConnectionError

from app.config import FRONTEND_URL
from app.database.job_repository import (
    claim_notification_send,
    mark_job_completed,
    mark_notification_sent,
)
from app.queue.producer import get_gateway_producer

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")

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
        content = (
            f"Hello,\n\n"
            f'Your video "{filename}" has been converted to MP3.\n\n'
            f"Sign in at {frontend_url} to download your file.\n\n"
            f"Job ID: {job_id}\n"
        )

        get_gateway_producer().publish_notification_event(
            recipient=recipient,
            subject=subject,
            content=content,
        )
        mark_notification_sent(job_id)
        logger.info(
            "Completion notification queued job_id=%s recipient=%s",
            job_id,
            recipient,
        )

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
                logger.warning(
                    "Conversion failed job_id=%s error=%s",
                    payload.get("job_id"),
                    payload.get("error_message"),
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

        while True:

            try:

                logger.info(
                    "Gateway consumer waiting on queue=%s",
                    self.video_completed_queue,
                )

                self.channel.basic_consume(
                    queue=self.video_completed_queue,
                    on_message_callback=self.process_message,
                )

                self.channel.start_consuming()

            except Exception as error:

                logger.error("Gateway consumer crashed: %s", str(error))

                time.sleep(5)

                self.reconnect()

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


def start_consumer():

    import threading

    global _consumer_instance, _consumer_thread

    if _consumer_thread and _consumer_thread.is_alive():
        return

    def _run():

        global _consumer_instance

        try:
            _consumer_instance = GatewayEventConsumer()
            _consumer_instance.start()
        except Exception as error:
            logger.error(
                "Gateway consumer failed to start: %s",
                str(error),
            )

    _consumer_thread = threading.Thread(
        target=_run,
        name="gateway-consumer",
        daemon=True,
    )

    _consumer_thread.start()

    logger.info("Gateway consumer startup initiated")


if __name__ == "__main__":

    start_consumer()

    while True:
        time.sleep(3600)
