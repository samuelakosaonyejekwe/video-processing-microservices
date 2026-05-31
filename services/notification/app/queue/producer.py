import json
import logging
import os
import time
import uuid

import pika
from pika.exceptions import AMQPConnectionError, AMQPChannelError

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")

logger = logging.getLogger(__name__)


class RabbitMQProducer:

    def __init__(self):

        self.rabbitmq_host = os.getenv("RABBITMQ_HOST")

        self.rabbitmq_port = int(os.getenv("RABBITMQ_PORT", "5672"))

        self.rabbitmq_username = os.getenv("RABBITMQ_USERNAME")

        self.rabbitmq_password = os.getenv("RABBITMQ_PASSWORD")

        self.notification_queue = os.getenv("NOTIFICATION_QUEUE")

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

                self.channel.queue_declare(queue=self.notification_queue, durable=True)

                logger.info("RabbitMQ connection established successfully")

                break

            except (AMQPConnectionError, AMQPChannelError) as error:

                logger.error("RabbitMQ connection failed: %s", str(error))

                logger.info("Retrying connection in 5 seconds...")

                time.sleep(5)

    def reconnect(self):

        logger.warning("Reconnecting to RabbitMQ...")

        self.close()

        self.connect()

    def publish_notification(self, event_type, payload):

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
                routing_key=self.notification_queue,
                body=json.dumps(event),
                properties=pika.BasicProperties(
                    delivery_mode=2,
                    content_type="application/json",
                    correlation_id=correlation_id,
                ),
            )

            logger.info("Notification event published successfully")

        except Exception as error:

            logger.error("Failed to publish notification event: %s", str(error))

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

            logger.info("RabbitMQ connection closed successfully")

        except Exception as error:

            logger.error("Failed to close RabbitMQ connection: %s", str(error))


_rabbitmq_producer = None


def get_notification_producer():
    global _rabbitmq_producer
    if _rabbitmq_producer is None:
        _rabbitmq_producer = RabbitMQProducer()
    return _rabbitmq_producer
