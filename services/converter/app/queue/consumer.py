import pika
import json
from app.config import (
    RABBITMQ_HOST,
    RABBITMQ_PORT
)
from app.ffmpeg.convert import convert_video_to_audio


def callback(ch, method, properties, body):

    message = json.loads(body)

    filename = message["filename"]

    print(f"Received conversion job: {filename}")

    convert_video_to_audio(filename)

    print(f"Conversion completed: {filename}")


def start_consumer():

    connection = pika.BlockingConnection(
        pika.ConnectionParameters(
            host=RABBITMQ_HOST,
            port=RABBITMQ_PORT
        )
    )

    channel = connection.channel()

    channel.queue_declare(queue="video_conversion")

    channel.basic_consume(
        queue="video_conversion",
        on_message_callback=callback,
        auto_ack=True
    )

    print("Waiting for conversion jobs...")

    channel.start_consuming()


if __name__ == "__main__":

    start_consumer()