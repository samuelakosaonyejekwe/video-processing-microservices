import json
import logging
import os
import re
import subprocess
import tempfile
import threading
import time
import uuid

import pika

from pika.exceptions import AMQPConnectionError, AMQPChannelError

from app.queue.producer import get_converter_producer
from shared.idempotency.redis_store import claim_once, release_claim
from shared.storage.s3_client import create_s3_client

logger = logging.getLogger(__name__)

# Queue messages come from another service (a trust boundary). job_id is used in
# local filesystem paths and S3 keys, so constrain it to a safe charset; s3_key
# must stay within the expected upload prefix and contain no traversal.
_SAFE_JOB_ID = re.compile(r"^[A-Za-z0-9_-]{1,128}$")
_ALLOWED_S3_PREFIX = "uploads/videos/"


def _validate_conversion_inputs(job_id: str, s3_key: str) -> None:
    if not _SAFE_JOB_ID.match(job_id):
        raise ValueError(f"Invalid job_id in conversion payload: {job_id!r}")
    if (
        not s3_key
        or ".." in s3_key
        or s3_key.startswith("/")
        or not s3_key.startswith(_ALLOWED_S3_PREFIX)
    ):
        raise ValueError(f"Invalid s3_key in conversion payload: {s3_key!r}")


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

        self.s3_audio_bucket = (
            os.getenv("S3_AUDIO_BUCKET")
            or os.getenv("AWS_S3_AUDIO_BUCKET")
            or self.s3_bucket_name
        )

        self.s3_audio_prefix = os.getenv("S3_AUDIO_OUTPUT_PREFIX", "outputs/audio/")

        self.temp_storage_path = os.getenv("TEMP_STORAGE_PATH", "/tmp")

        self.max_retry_attempts = int(os.getenv("MAX_CONVERSION_RETRIES", "3"))

        self.connection = None

        self.channel = None

        self.s3_client = create_s3_client()

        self._should_stop = False

        self._ready_event = threading.Event()

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

                from shared.messaging.queue_setup import declare_pipeline_queues

                self.channel = declare_pipeline_queues(
                    self.channel,
                    video_upload_queue=self.video_upload_queue,
                    video_upload_retry_queue=self.video_upload_retry_queue,
                    video_upload_dlq=self.video_upload_dlq,
                    declare_gateway_events=False,
                    declare_upload_pipeline=True,
                )

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

        logger.info(
            "Uploading converted audio to S3 bucket=%s key=%s",
            self.s3_audio_bucket,
            audio_s3_key,
        )

        self.s3_client.upload_file(local_audio_path, self.s3_audio_bucket, audio_s3_key)

    def convert_video_to_audio(self, input_video_path, output_audio_path):

        logger.info("Starting FFmpeg conversion...")

        # Use the explicit LAME MP3 encoder. "-acodec mp3" names a codec id, not
        # an encoder, and fails with "Unknown encoder 'mp3'" on many ffmpeg builds.
        ffmpeg_command = [
            "ffmpeg",
            "-y",
            "-i",
            input_video_path,
            "-vn",
            "-c:a",
            "libmp3lame",
            "-b:a",
            "192k",
            output_audio_path,
        ]

        timeout_seconds = int(os.getenv("MAX_CONVERSION_TIMEOUT_SECONDS", "90"))
        subprocess.run(ffmpeg_command, check=True, timeout=timeout_seconds)

        logger.info("FFmpeg conversion completed successfully")

    def process_message(self, ch, method, properties, body):

        job_id = None
        user_id = None
        filename = None
        correlation_id = None
        retry_count = 0
        message = {}
        payload = {}

        try:

            message = json.loads(body)

            correlation_id = message.get("correlation_id")

            payload = message.get("payload", {})

            user_id = payload.get("user_id")

            filename = payload.get("filename")

            s3_key = payload.get("s3_key")

            job_id = payload.get("job_id")

            if not s3_key:

                raise ValueError("Missing s3_key in conversion payload")

            if not job_id:

                job_id = str(uuid.uuid4())

            _validate_conversion_inputs(job_id, s3_key)

            retry_count = int(payload.get("retry_count", 0))

            if job_id and not claim_once(f"conversion:{job_id}", ttl_seconds=86400):
                logger.info(
                    "Skipping duplicate conversion job_id=%s correlation_id=%s",
                    job_id,
                    correlation_id,
                )
                ch.basic_ack(delivery_tag=method.delivery_tag)
                return

            logger.info(
                "Processing conversion request " "correlation_id=%s job_id=%s",
                correlation_id,
                job_id,
            )

            with tempfile.TemporaryDirectory(
                dir=self.temp_storage_path
            ) as temp_directory:

                local_video_path = os.path.join(temp_directory, f"{job_id}.mp4")

                local_audio_path = os.path.join(temp_directory, f"{job_id}.mp3")

                self.download_video(s3_key, local_video_path)

                self.convert_video_to_audio(local_video_path, local_audio_path)

                audio_s3_key = f"{self.s3_audio_prefix.rstrip('/')}/{job_id}.mp3"

                self.upload_audio(local_audio_path, audio_s3_key)

                get_converter_producer().publish_conversion_completed_event(
                    job_id=job_id,
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

            if (
                job_id
                and retry_count < self.max_retry_attempts
                and self.video_upload_retry_queue
            ):
                # Release the idempotency claim so the retried delivery is not
                # skipped as a duplicate — otherwise the very first failure would
                # permanently drop the job.
                release_claim(f"conversion:{job_id}")
                retry_payload = dict(payload)
                retry_payload["retry_count"] = retry_count + 1
                retry_message = {
                    "correlation_id": correlation_id,
                    "event_type": message.get("event_type", "video_uploaded"),
                    "payload": retry_payload,
                }
                try:
                    self.channel.basic_publish(
                        exchange="",
                        routing_key=self.video_upload_retry_queue,
                        body=json.dumps(retry_message),
                        properties=pika.BasicProperties(delivery_mode=2),
                    )
                    ch.basic_ack(delivery_tag=method.delivery_tag)
                    return
                except Exception as retry_error:
                    logger.error("Failed to publish retry message: %s", retry_error)

            if job_id:
                failure_published = False
                try:
                    get_converter_producer().publish_conversion_failed_event(
                        job_id=job_id,
                        user_id=user_id,
                        original_filename=filename,
                        error_message=str(error),
                    )
                    failure_published = True
                except Exception as publish_error:
                    logger.error(
                        "Failed to publish conversion failed event: %s",
                        publish_error,
                    )

                if failure_published:
                    ch.basic_ack(delivery_tag=method.delivery_tag)
                    return

            ch.basic_nack(delivery_tag=method.delivery_tag, requeue=False)

    def start(self):

        while not self._should_stop:

            try:

                logger.info("Converter consumer waiting for conversion events...")

                self.channel.basic_consume(
                    queue=self.video_upload_queue,
                    on_message_callback=self.process_message,
                )

                self._ready_event.set()

                self.channel.start_consuming()

            except Exception as error:

                if self._should_stop:
                    break

                logger.error("Converter consumer crashed: %s", str(error))

                time.sleep(5)

                self.reconnect()

    def stop(self) -> None:
        self._should_stop = True
        self._ready_event.clear()
        try:
            if self.channel and self.channel.is_open:
                self.channel.stop_consuming()
        except Exception as error:
            logger.warning("Converter consumer stop_consuming failed: %s", error)
        self.close()

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
_on_ready_callback = None


def start_consumer(on_ready=None):

    import threading

    global _consumer_instance, _consumer_thread, _on_ready_callback

    _on_ready_callback = on_ready

    if _consumer_thread and _consumer_thread.is_alive():
        return

    def _run():

        global _consumer_instance

        try:
            _consumer_instance = ConverterEventConsumer()

            if _on_ready_callback:

                def _notify_ready():
                    if _consumer_instance._ready_event.wait(timeout=60):
                        _on_ready_callback()

                threading.Thread(
                    target=_notify_ready,
                    name="converter-consumer-ready",
                    daemon=True,
                ).start()

            _consumer_instance.start()
        except Exception as error:
            logger.error(
                "Converter consumer failed to start: %s",
                str(error),
            )

    _consumer_thread = threading.Thread(
        target=_run,
        name="converter-consumer",
        daemon=False,
    )

    _consumer_thread.start()

    logger.info("Converter consumer startup initiated")


def stop_consumer() -> None:
    global _consumer_instance, _consumer_thread

    if _consumer_instance is not None:
        _consumer_instance.stop()
        _consumer_instance = None

    if _consumer_thread and _consumer_thread.is_alive():
        _consumer_thread.join(timeout=15)
    _consumer_thread = None


if __name__ == "__main__":

    start_consumer()

    while True:
        time.sleep(3600)
