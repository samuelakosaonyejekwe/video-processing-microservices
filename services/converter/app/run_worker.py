import logging
import time

from app.queue.consumer import start_consumer, stop_consumer
from shared.logging.logger import configure_logging
from shared.runtime.graceful_shutdown import register_shutdown_handler
from shared.runtime.worker_ready import WorkerReadyMarker

logger = logging.getLogger(__name__)
ready_marker = WorkerReadyMarker("/tmp/worker-ready")


def _shutdown() -> None:
    logger.info("Converter worker shutting down...")
    stop_consumer()
    ready_marker.clear()


def main() -> None:
    configure_logging("converter-worker")
    register_shutdown_handler(_shutdown)

    logger.info("Starting converter queue worker...")
    start_consumer(on_ready=ready_marker.mark_ready)

    if not ready_marker.wait_until_ready(timeout=60):
        logger.error("Converter queue worker failed to become ready")
        raise SystemExit(1)

    logger.info("Converter queue worker is ready")

    try:
        while True:
            time.sleep(3600)
    finally:
        _shutdown()


if __name__ == "__main__":
    main()
