import logging
import time
from pathlib import Path

from app.queue.consumer import start_consumer

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger(__name__)

READY_FILE = Path("/tmp/worker-ready")


def main() -> None:
    logger.info("Starting converter queue worker...")
    start_consumer()
    READY_FILE.touch()
    logger.info("Converter queue worker is ready")

    while True:
        time.sleep(3600)


if __name__ == "__main__":
    main()
