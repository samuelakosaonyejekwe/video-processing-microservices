import pika
import json

from app.config import (
    RABBITMQ_HOST,
    RABBITMQ_PORT
)

from app.email.send_email import send_email


def callback(ch, method, properties, body):

    message = json.loads(body)

    recipient = message.get("recipient")
    subject = message.get("subject")
    content = message.get("content")

    send_email(
        recipient,
        subject,
        content
    )

    print(
        f"Notification sent to {recipient}"
    )


def start_consumer():

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

    channel.basic_consume(
        queue="notifications",
        on_message_callback=callback,
        auto_ack=True
    )

    print(
        "Waiting for notifications..."
    )

    channel.start_consuming()


if __name__ == "__main__":

    start_consumer()