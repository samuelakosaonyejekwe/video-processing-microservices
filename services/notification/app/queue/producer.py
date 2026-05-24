import pika
import json
from app.config import (
    RABBITMQ_HOST,
    RABBITMQ_PORT
)


def publish_notification(message_data: dict):

    connection = pika.BlockingConnection(
        pika.ConnectionParameters(
            host=RABBITMQ_HOST,
            port=RABBITMQ_PORT
        )
    )

    channel = connection.channel()

    channel.queue_declare(
        queue="notifications"
    )

    channel.basic_publish(
        exchange="",
        routing_key="notifications",
        body=json.dumps(message_data)
    )

    connection.close()