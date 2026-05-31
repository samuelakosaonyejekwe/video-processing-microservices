import json
import logging
import os
import time

import pika

from pika.exceptions import AMQPConnectionError, AMQPChannelError

from app.email.send_email import send_email
from app.websocket.events import broadcast_event_sync

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
                self.channel.queue_declare(queue=self.retry_queue, durable=True)

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

        try:

            message = json.loads(body)

            recipient = message.get("payload", {}).get("recipient")

            subject = message.get("payload", {}).get("subject")

            content = message.get("payload", {}).get("content")

            correlation_id = message.get("correlation_id")

            if not recipient:

                raise ValueError("Missing recipient in notification payload")

            if not send_email(recipient, subject, content):
                raise RuntimeError(f"Email delivery failed for recipient={recipient}")

            broadcast_event_sync(
                {
                    "type": "notification_sent",
                    "recipient": recipient,
                    "correlation_id": correlation_id,
                    "subject": subject,
                }
            )

            logger.info(
                "Notification sent successfully " "to %s " "correlation_id=%s",
                recipient,
                correlation_id,
            )

            ch.basic_ack(delivery_tag=method.delivery_tag)

        except Exception as error:

            logger.error("Notification processing failed: %s", str(error))

            try:

                self.channel.basic_publish(
                    exchange="",
                    routing_key=self.retry_queue,
                    body=body,
                    properties=pika.BasicProperties(delivery_mode=2),
                )

            except Exception as retry_error:

                logger.error("Retry queue publish failed: %s", str(retry_error))

            ch.basic_nack(delivery_tag=method.delivery_tag, requeue=False)

    def start(self):

        while True:

            try:

                logger.info("Waiting for notification events...")

                self.channel.basic_consume(
                    queue=self.notification_queue,
                    on_message_callback=self.process_message,
                )

                self.channel.start_consuming()

            except Exception as error:

                logger.error("Consumer crashed: %s", str(error))

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

            logger.info("RabbitMQ consumer connection closed")

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
            _consumer_instance = NotificationConsumer()
            _consumer_instance.start()
        except Exception as error:
            logger.error(
                "Notification consumer failed to start: %s",
                str(error),
            )

    _consumer_thread = threading.Thread(
        target=_run,
        name="notification-consumer",
        daemon=True,
    )

    _consumer_thread.start()

    logger.info("Notification consumer startup initiated")


if __name__ == "__main__":

    start_consumer()

    import time

    while True:
        time.sleep(3600)
