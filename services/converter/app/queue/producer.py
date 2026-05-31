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


class ConverterEventProducer:

    def __init__(self):

        self.rabbitmq_host = os.getenv("RABBITMQ_HOST")

        self.rabbitmq_port = int(os.getenv("RABBITMQ_PORT", "5672"))

        self.rabbitmq_username = os.getenv("RABBITMQ_USERNAME")

        self.rabbitmq_password = os.getenv("RABBITMQ_PASSWORD")

        self.video_upload_queue = os.getenv("VIDEO_UPLOAD_QUEUE")

        self.notification_queue = os.getenv("NOTIFICATION_QUEUE")

        self.gateway_events_queue = os.getenv("GATEWAY_EVENTS_QUEUE")

        self.video_completed_queue = os.getenv("VIDEO_COMPLETED_QUEUE")

        self.video_failed_queue = os.getenv("VIDEO_FAILED_QUEUE")

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
            "VIDEO_COMPLETED_QUEUE",
            "VIDEO_FAILED_QUEUE",
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

                logger.info("Connecting converter producer to RabbitMQ...")

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

                self.channel.queue_declare(queue=self.video_upload_queue, durable=True)

                self.channel.queue_declare(queue=self.notification_queue, durable=True)

                self.channel.queue_declare(
                    queue=self.gateway_events_queue, durable=True
                )

                self.channel.queue_declare(
                    queue=self.video_completed_queue, durable=True
                )

                self.channel.queue_declare(queue=self.video_failed_queue, durable=True)

                logger.info("Converter RabbitMQ producer connected successfully")

                break

            except (AMQPConnectionError, AMQPChannelError) as error:

                logger.error("RabbitMQ connection failed: %s", str(error))

                logger.info("Retrying RabbitMQ connection in 5 seconds...")

                time.sleep(5)

    def reconnect(self):

        logger.warning("Reconnecting converter RabbitMQ producer...")

        self.close()

        self.connect()

    def publish_conversion_completed_event(
        self, job_id, user_id, original_filename, audio_s3_key, output_format
    ):

        try:

            correlation_id = str(uuid.uuid4())

            event = build_event(
                "video_conversion_completed",
                {
                    "job_id": job_id,
                    "user_id": user_id,
                    "original_filename": original_filename,
                    "audio_s3_key": audio_s3_key,
                    "output_format": output_format,
                },
                correlation_id,
            )

            self.channel.basic_publish(
                exchange="",
                routing_key=self.video_completed_queue,
                body=json.dumps(event),
                properties=pika.BasicProperties(
                    delivery_mode=2,
                    content_type="application/json",
                    correlation_id=correlation_id,
                ),
            )

            logger.info(
                "Conversion completed event published " "correlation_id=%s",
                correlation_id,
            )

            return correlation_id

        except Exception as error:

            logger.error("Failed to publish conversion completed event: %s", str(error))

            self.reconnect()

            raise error

    def publish_conversion_failed_event(
        self, job_id, user_id, original_filename, error_message
    ):

        try:

            correlation_id = str(uuid.uuid4())

            event = build_event(
                "video_conversion_failed",
                {
                    "job_id": job_id,
                    "user_id": user_id,
                    "original_filename": original_filename,
                    "error_message": error_message,
                },
                correlation_id,
            )

            self.channel.basic_publish(
                exchange="",
                routing_key=self.video_completed_queue,
                body=json.dumps(event),
                properties=pika.BasicProperties(
                    delivery_mode=2,
                    content_type="application/json",
                    correlation_id=correlation_id,
                ),
            )

            logger.info(
                "Conversion failed event published " "correlation_id=%s", correlation_id
            )

            return correlation_id

        except Exception as error:

            logger.error("Failed to publish conversion failed event: %s", str(error))

            self.reconnect()

            raise error

    def publish_notification_event(self, recipient, subject, content):

        try:

            correlation_id = str(uuid.uuid4())

            event = {
                "event_id": str(uuid.uuid4()),
                "correlation_id": correlation_id,
                "event_type": "notification_requested",
                "timestamp": int(time.time()),
                "payload": {
                    "recipient": recipient,
                    "subject": subject,
                    "content": content,
                },
            }

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
                "Notification event published " "correlation_id=%s", correlation_id
            )

            return correlation_id

        except Exception as error:

            logger.error("Failed to publish notification event: %s", str(error))

            self.reconnect()

            raise error

    def publish_gateway_event(self, event_type, payload):

        try:

            correlation_id = str(uuid.uuid4())

            event = {
                "event_id": str(uuid.uuid4()),
                "correlation_id": correlation_id,
                "event_type": event_type,
                "timestamp": int(time.time()),
                "payload": payload,
            }

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
                "Gateway event published " "event_type=%s correlation_id=%s",
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

            logger.info("Converter RabbitMQ producer connection closed")

        except Exception as error:

            logger.error("Failed to close RabbitMQ connection: %s", str(error))


_producer_instance = None


def get_converter_producer() -> ConverterEventProducer:

    global _producer_instance

    if _producer_instance is None:
        _producer_instance = ConverterEventProducer()

    return _producer_instance


def publish_conversion_job(
    job_id: str,
    filename: str,
    s3_key: str,
    content_type: str,
    user_id: str = "anonymous",
) -> str:

    import json
    import time

    producer = get_converter_producer()

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

    producer.channel.basic_publish(
        exchange="",
        routing_key=producer.video_upload_queue,
        body=json.dumps(event),
        properties=pika.BasicProperties(
            delivery_mode=2,
            content_type="application/json",
            correlation_id=correlation_id,
        ),
    )

    logger.info(
        "Conversion job queued correlation_id=%s job_id=%s",
        correlation_id,
        job_id,
    )

    return correlation_id
