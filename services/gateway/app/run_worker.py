import logging
import time
from pathlib import Path

from app.database.job_repository import ensure_job_indexes
from app.database.mongo_client import close_mongo_client
from app.queue.consumer import start_consumer
from app.queue.producer import get_gateway_producer

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger(__name__)

READY_FILE = Path("/tmp/worker-ready")


def main() -> None:
    logger.info("Starting gateway queue worker...")
    try:
        ensure_job_indexes()
    except Exception as error:
        logger.warning("MongoDB index setup failed: %s", error)

    start_consumer()
    READY_FILE.touch()
    logger.info("Gateway queue worker is ready")

    try:
        while True:
            time.sleep(3600)
    finally:
        READY_FILE.unlink(missing_ok=True)
        try:
            get_gateway_producer().close()
        except Exception:
            pass
        close_mongo_client()


if __name__ == "__main__":
    main()
