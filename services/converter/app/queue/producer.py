import pika
import json
from app.config import (
    RABBITMQ_HOST,
    RABBITMQ_PORT
)


def publish_conversion_job(filename: str):

    connection = pika.BlockingConnection(
        pika.ConnectionParameters(
            host=RABBITMQ_HOST,
            port=RABBITMQ_PORT
        )
    )

    channel = connection.channel()

    channel.queue_declare(queue="video_conversion")

    message = {
        "filename": filename
    }

    channel.basic_publish(
        exchange="",
        routing_key="video_conversion",
        body=json.dumps(message)
    )

    connection.close()