import json
import logging
import os
import subprocess
import tempfile
import time
import uuid

import boto3
import pika

from pika.exceptions import AMQPConnectionError, AMQPChannelError

from app.queue.producer import get_converter_producer

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")

logger = logging.getLogger(__name__)


class ConverterEventConsumer:

    def __init__(self):

        self.rabbitmq_host = os.getenv("RABBITMQ_HOST")

        self.rabbitmq_port = int(os.getenv("RABBITMQ_PORT", "5672"))

        self.rabbitmq_username = os.getenv("RABBITMQ_USERNAME")

        self.rabbitmq_password = os.getenv("RABBITMQ_PASSWORD")

        self.video_upload_queue = os.getenv("VIDEO_UPLOAD_QUEUE")

        self.video_upload_retry_queue = os.getenv("VIDEO_UPLOAD_RETRY_QUEUE")

        self.video_upload_dlq = os.getenv("VIDEO_UPLOAD_DLQ")

        self.aws_region = os.getenv("AWS_REGION")

        self.s3_bucket_name = os.getenv("S3_BUCKET_NAME")

        self.temp_storage_path = os.getenv("TEMP_STORAGE_PATH", "/tmp")

        self.connection = None

        self.channel = None

        self.s3_client = boto3.client("s3", region_name=self.aws_region)

        self.validate_environment()

        self.connect()

    def validate_environment(self):

        if not os.getenv("S3_BUCKET_NAME"):
            bucket = (
                os.getenv("S3_UPLOAD_BUCKET")
                or os.getenv("AWS_S3_VIDEO_BUCKET")
                or os.getenv("AWS_S3_BUCKET")
            )
            if bucket:
                os.environ["S3_BUCKET_NAME"] = bucket
                self.s3_bucket_name = bucket

        required_environment_variables = [
            "RABBITMQ_HOST",
            "RABBITMQ_PORT",
            "RABBITMQ_USERNAME",
            "RABBITMQ_PASSWORD",
            "VIDEO_UPLOAD_QUEUE",
            "AWS_REGION",
            "S3_BUCKET_NAME",
        ]

        optional_defaults = {
            "VIDEO_UPLOAD_RETRY_QUEUE": "video-upload-retry-queue",
            "VIDEO_UPLOAD_DLQ": "video-upload-dlq",
        }

        for key, default in optional_defaults.items():
            if not os.getenv(key):
                os.environ[key] = default

        missing_variables = [
            variable
            for variable in required_environment_variables
            if not os.getenv(variable)
        ]

        if missing_variables:
            raise ValueError(
                f"Missing required environment variables: {missing_variables}"
            )

    def connect(self):

        while True:

            try:

                logger.info("Connecting converter consumer to RabbitMQ...")

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

                self.channel.queue_declare(
                    queue=self.video_upload_retry_queue, durable=True
                )

                self.channel.queue_declare(queue=self.video_upload_dlq, durable=True)

                self.channel.basic_qos(prefetch_count=1)

                logger.info("Converter RabbitMQ consumer connected successfully")

                break

            except (AMQPConnectionError, AMQPChannelError) as error:

                logger.error("RabbitMQ connection failed: %s", str(error))

                logger.info("Retrying RabbitMQ connection in 5 seconds...")

                time.sleep(5)

    def reconnect(self):

        logger.warning("Reconnecting converter RabbitMQ consumer...")

        self.close()

        self.connect()

    def download_video(self, s3_key, local_video_path):

        logger.info("Downloading video from S3: %s", s3_key)

        self.s3_client.download_file(self.s3_bucket_name, s3_key, local_video_path)

    def upload_audio(self, local_audio_path, audio_s3_key):

        logger.info("Uploading converted audio to S3: %s", audio_s3_key)

        self.s3_client.upload_file(local_audio_path, self.s3_bucket_name, audio_s3_key)

    def convert_video_to_audio(self, input_video_path, output_audio_path):

        logger.info("Starting FFmpeg conversion...")

        ffmpeg_command = [
            "ffmpeg",
            "-y",
            "-i",
            input_video_path,
            "-vn",
            "-acodec",
            "mp3",
            output_audio_path,
        ]

        subprocess.run(ffmpeg_command, check=True)

        logger.info("FFmpeg conversion completed successfully")

    def process_message(self, ch, method, properties, body):

        try:

            message = json.loads(body)

            correlation_id = message.get("correlation_id")

            payload = message.get("payload", {})

            user_id = payload.get("user_id")

            filename = payload.get("filename")

            s3_key = payload.get("s3_key")

            if not s3_key:

                raise ValueError("Missing s3_key in conversion payload")

            logger.info(
                "Processing conversion request " "correlation_id=%s", correlation_id
            )

            unique_id = str(uuid.uuid4())

            with tempfile.TemporaryDirectory(
                dir=self.temp_storage_path
            ) as temp_directory:

                local_video_path = os.path.join(temp_directory, f"{unique_id}.mp4")

                local_audio_path = os.path.join(temp_directory, f"{unique_id}.mp3")

                self.download_video(s3_key, local_video_path)

                self.convert_video_to_audio(local_video_path, local_audio_path)

                audio_s3_key = f"converted-audio/" f"{unique_id}.mp3"

                self.upload_audio(local_audio_path, audio_s3_key)

                get_converter_producer().publish_conversion_completed_event(
                    user_id=user_id,
                    original_filename=filename,
                    audio_s3_key=audio_s3_key,
                    output_format="mp3",
                )

                ch.basic_ack(delivery_tag=method.delivery_tag)

                logger.info(
                    "Conversion completed successfully " "correlation_id=%s",
                    correlation_id,
                )

        except Exception as error:

            logger.error("Conversion processing failed: %s", str(error))

            try:

                self.channel.basic_publish(
                    exchange="",
                    routing_key=self.video_upload_retry_queue,
                    body=body,
                    properties=pika.BasicProperties(delivery_mode=2),
                )

            except Exception as retry_error:

                logger.error("Retry queue publish failed: %s", str(retry_error))

            try:

                failed_message = {"error": str(error), "failed_message": body.decode()}

                self.channel.basic_publish(
                    exchange="",
                    routing_key=self.video_upload_dlq,
                    body=json.dumps(failed_message),
                    properties=pika.BasicProperties(delivery_mode=2),
                )

            except Exception as dlq_error:

                logger.error("DLQ publish failed: %s", str(dlq_error))

            ch.basic_nack(delivery_tag=method.delivery_tag, requeue=False)

    def start(self):

        while True:

            try:

                logger.info("Converter consumer waiting for conversion events...")

                self.channel.basic_consume(
                    queue=self.video_upload_queue,
                    on_message_callback=self.process_message,
                )

                self.channel.start_consuming()

            except Exception as error:

                logger.error("Converter consumer crashed: %s", str(error))

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

            logger.info("Converter RabbitMQ consumer connection closed")

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
            _consumer_instance = ConverterEventConsumer()
            _consumer_instance.start()
        except Exception as error:
            logger.error(
                "Converter consumer failed to start: %s",
                str(error),
            )

    _consumer_thread = threading.Thread(
        target=_run,
        name="converter-consumer",
        daemon=True,
    )

    _consumer_thread.start()

    logger.info("Converter consumer startup initiated")


if __name__ == "__main__":

    start_consumer()

    while True:
        time.sleep(3600)
