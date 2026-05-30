import os
import time
import pika


def get_connection():

    while True:

        try:

            credentials = pika.PlainCredentials(
                os.getenv("RABBITMQ_USERNAME"),
                os.getenv("RABBITMQ_PASSWORD")
            )

            parameters = pika.ConnectionParameters(
                host=os.getenv("RABBITMQ_HOST"),
                port=int(os.getenv("RABBITMQ_PORT")),
                credentials=credentials,
                heartbeat=600,
                blocked_connection_timeout=300
            )

            return pika.BlockingConnection(parameters)

        except Exception:

            time.sleep(5)