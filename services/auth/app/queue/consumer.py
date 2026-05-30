import json
import logging
import os
import time

import pika

from pika.exceptions import AMQPConnectionError, AMQPChannelError

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")

logger = logging.getLogger(__name__)


class AuthEventConsumer:

    def __init__(self):

        self.rabbitmq_host = os.getenv("RABBITMQ_HOST")

        self.rabbitmq_port = int(os.getenv("RABBITMQ_PORT", "5672"))

        self.rabbitmq_username = os.getenv("RABBITMQ_USERNAME")

        self.rabbitmq_password = os.getenv("RABBITMQ_PASSWORD")

        self.auth_events_queue = os.getenv("AUTH_EVENTS_QUEUE")

        self.auth_retry_queue = os.getenv("AUTH_RETRY_QUEUE")

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
            "AUTH_EVENTS_QUEUE",
            "AUTH_RETRY_QUEUE",
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

                logger.info("Connecting auth consumer to RabbitMQ...")

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

                self.channel.queue_declare(queue=self.auth_events_queue, durable=True)

                self.channel.basic_qos(prefetch_count=1)

                logger.info("Auth RabbitMQ consumer connected successfully")

                break

            except (AMQPConnectionError, AMQPChannelError) as error:

                logger.error("RabbitMQ connection failed: %s", str(error))

                logger.info("Retrying RabbitMQ connection in 5 seconds...")

                time.sleep(5)

    def reconnect(self):

        logger.warning("Reconnecting auth RabbitMQ consumer...")

        self.close()

        self.connect()

    def process_message(self, ch, method, properties, body):

        try:

            message = json.loads(body)

            correlation_id = message.get("correlation_id")

            event_type = message.get("event_type")

            payload = message.get("payload", {})

            logger.info(
                "Auth consumer received event " "event_type=%s correlation_id=%s",
                event_type,
                correlation_id,
            )

            if event_type == "user_registered":

                logger.info("Processing user registration event")

            elif event_type == "password_reset_requested":

                logger.info("Processing password reset event")

            elif event_type == "token_revoked":

                logger.info("Processing token revocation event")

            elif event_type == "suspicious_login_detected":

                logger.warning("Processing suspicious login event")

            else:

                logger.warning("Unknown auth event type received: %s", event_type)

            ch.basic_ack(delivery_tag=method.delivery_tag)

        except Exception as error:

            logger.error("Auth consumer processing failed: %s", str(error))

            try:

                self.channel.basic_publish(
                    exchange="",
                    routing_key=self.auth_retry_queue,
                    body=body,
                    properties=pika.BasicProperties(delivery_mode=2),
                )

            except Exception as retry_error:

                logger.error("Retry queue publish failed: %s", str(retry_error))

            ch.basic_nack(delivery_tag=method.delivery_tag, requeue=False)

    def start(self):

        while True:

            try:

                logger.info("Auth consumer waiting for events...")

                self.channel.basic_consume(
                    queue=self.auth_events_queue,
                    on_message_callback=self.process_message,
                )

                self.channel.start_consuming()

            except Exception as error:

                logger.error("Auth consumer crashed: %s", str(error))

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

            logger.info("Auth RabbitMQ consumer connection closed")

        except Exception as error:

            logger.error("Failed to close RabbitMQ connection: %s", str(error))


if __name__ == "__main__":

    consumer = AuthEventConsumer()

    consumer.start()
