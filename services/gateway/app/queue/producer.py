import json
import logging
import os
import time
import uuid

import pika

from pika.exceptions import AMQPConnectionError, AMQPChannelError
from shared.events.schema import build_event

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")

logger = logging.getLogger(__name__)


class GatewayEventProducer:

    def __init__(self):

        self.rabbitmq_host = os.getenv("RABBITMQ_HOST")

        self.rabbitmq_port = int(os.getenv("RABBITMQ_PORT", "5672"))

        self.rabbitmq_username = os.getenv("RABBITMQ_USERNAME")

        self.rabbitmq_password = os.getenv("RABBITMQ_PASSWORD")

        self.video_upload_queue = os.getenv("VIDEO_UPLOAD_QUEUE")

        self.notification_queue = os.getenv("NOTIFICATION_QUEUE")

        self.gateway_events_queue = os.getenv("GATEWAY_EVENTS_QUEUE")

        self.video_completed_queue = os.getenv(
            "VIDEO_COMPLETED_QUEUE", "video-completed-queue"
        )

        self.rabbitmq_exchange = os.getenv("RABBITMQ_EXCHANGE")

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
            "VIDEO_UPLOAD_QUEUE",
            "NOTIFICATION_QUEUE",
            "GATEWAY_EVENTS_QUEUE",
            "RABBITMQ_EXCHANGE",
        ]

        missing_variables = []

        for variable in required_environment_variables:

            if not os.getenv(variable):

                missing_variables.append(variable)

        if missing_variables:

            raise ValueError(
                f"Missing required environment variables: " f"{missing_variables}"
            )

    def connect(self, max_attempts: int = 12):

        for attempt in range(max_attempts):

            try:

                logger.info("Connecting gateway producer to RabbitMQ...")

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
                    gateway_events_queue=self.gateway_events_queue,
                    video_completed_queue=self.video_completed_queue,
                    notification_queue=self.notification_queue,
                    video_upload_queue=self.video_upload_queue,
                    declare_upload_pipeline=True,
                )

                logger.info("Gateway RabbitMQ producer connected successfully")

                return

            except (AMQPConnectionError, AMQPChannelError) as error:

                logger.error("RabbitMQ connection failed: %s", str(error))

                if attempt >= max_attempts - 1:
                    raise

                logger.info("Retrying RabbitMQ connection in 5 seconds...")

                time.sleep(5)

    def reconnect(self):

        logger.warning("Reconnecting gateway producer...")

        self.close()

        self.connect()

    def publish_video_upload_event(
        self, job_id, user_id, filename, s3_key, content_type
    ):

        try:

            correlation_id = str(uuid.uuid4())

            event = build_event(
                "video_uploaded",
                {
                    "job_id": job_id,
                    "user_id": user_id,
                    "filename": filename,
                    "s3_key": s3_key,
                    "content_type": content_type,
                },
                correlation_id,
            )

            self.channel.basic_publish(
                exchange="",
                routing_key=self.video_upload_queue,
                body=json.dumps(event),
                properties=pika.BasicProperties(
                    delivery_mode=2,
                    content_type="application/json",
                    correlation_id=correlation_id,
                ),
            )

            logger.info(
                "Video upload event published successfully " "correlation_id=%s",
                correlation_id,
            )

            return correlation_id

        except Exception as error:

            logger.error("Failed to publish video upload event: %s", str(error))

            self.reconnect()

            raise error

    def publish_notification_event(self, recipient, subject, content, job_id=None):

        try:

            correlation_id = str(uuid.uuid4())

            event = build_event(
                "notification_requested",
                {
                    "recipient": recipient,
                    "subject": subject,
                    "content": content,
                    "job_id": job_id,
                },
                correlation_id,
            )

            self.channel.basic_publish(
                exchange="",
                routing_key=self.notification_queue,
                body=json.dumps(event),
                properties=pika.BasicProperties(
                    delivery_mode=2,
                    content_type="application/json",
                    correlation_id=correlation_id,
                ),
            )

            logger.info(
                "Notification event published successfully " "correlation_id=%s",
                correlation_id,
            )

            return correlation_id

        except Exception as error:

            logger.error("Failed to publish notification event: %s", str(error))

            self.reconnect()

            raise error

    def publish_gateway_event(self, event_type, payload):

        try:

            correlation_id = str(uuid.uuid4())

            event = build_event(event_type, payload, correlation_id)

            self.channel.basic_publish(
                exchange="",
                routing_key=self.gateway_events_queue,
                body=json.dumps(event),
                properties=pika.BasicProperties(
                    delivery_mode=2,
                    content_type="application/json",
                    correlation_id=correlation_id,
                ),
            )

            logger.info(
                "Gateway event published successfully "
                "event_type=%s correlation_id=%s",
                event_type,
                correlation_id,
            )

            return correlation_id

        except Exception as error:

            logger.error("Failed to publish gateway event: %s", str(error))

            self.reconnect()

            raise error

    def close(self):

        try:

            if self.channel:

                if self.channel.is_open:

                    self.channel.close()

            if self.connection:

                if self.connection.is_open:

                    self.connection.close()

            logger.info("Gateway RabbitMQ producer connection closed")

        except Exception as error:

            logger.error("Failed to close RabbitMQ connection: %s", str(error))


_producer_instance = None


def get_gateway_producer() -> GatewayEventProducer:

    global _producer_instance

    if _producer_instance is None:
        _producer_instance = GatewayEventProducer()

    return _producer_instance
