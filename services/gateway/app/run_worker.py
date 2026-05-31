import logging
import time

from app.database.job_repository import ensure_job_indexes
from app.database.mongo_client import close_mongo_client
from app.queue.consumer import start_consumer, stop_consumer
from app.queue.producer import get_gateway_producer
from shared.logging.logger import configure_logging
from shared.runtime.graceful_shutdown import register_shutdown_handler
from shared.runtime.worker_ready import WorkerReadyMarker

logger = logging.getLogger(__name__)
ready_marker = WorkerReadyMarker("/tmp/worker-ready")


def _shutdown() -> None:
    logger.info("Gateway worker shutting down...")
    stop_consumer()
    ready_marker.clear()
    try:
        get_gateway_producer().close()
    except Exception as error:
        logger.warning("Gateway producer close failed: %s", error)
    close_mongo_client()


def main() -> None:
    configure_logging("gateway-worker")
    register_shutdown_handler(_shutdown)

    logger.info("Starting gateway queue worker...")
    try:
        ensure_job_indexes()
    except Exception as error:
        logger.warning("MongoDB index setup failed: %s", error)

    start_consumer(on_ready=ready_marker.mark_ready)

    if not ready_marker.wait_until_ready(timeout=60):
        logger.error("Gateway queue worker failed to become ready")
        raise SystemExit(1)

    logger.info("Gateway queue worker is ready")

    try:
        while True:
            time.sleep(3600)
    finally:
        _shutdown()


if __name__ == "__main__":
    main()
