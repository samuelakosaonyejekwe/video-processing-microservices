import json
import logging
import os
import sys
from datetime import datetime, timezone


def configure_logging(service_name: str | None = None) -> None:
    level_name = os.getenv("LOG_LEVEL", "INFO").upper()
    level = getattr(logging, level_name, logging.INFO)
    service = service_name or os.getenv("APP_NAME", "video-converter")

    if os.getenv("LOG_FORMAT", "json").lower() == "json":
        try:
            from pythonjsonlogger import jsonlogger

            handler = logging.StreamHandler(sys.stdout)
            formatter = jsonlogger.JsonFormatter(
                "%(asctime)s %(levelname)s %(name)s %(message)s "
                "%(service)s %(correlation_id)s %(job_id)s"
            )
            handler.setFormatter(formatter)
        except ImportError:
            handler = logging.StreamHandler(sys.stdout)
            handler.setFormatter(
                logging.Formatter("%(asctime)s %(levelname)s %(name)s %(message)s")
            )
    else:
        handler = logging.StreamHandler(sys.stdout)
        handler.setFormatter(
            logging.Formatter("%(asctime)s %(levelname)s %(name)s %(message)s")
        )

    root = logging.getLogger()
    root.handlers.clear()
    root.addHandler(handler)
    root.setLevel(level)

    logging.LoggerAdapter.__init__  # noqa: B018 - ensure module loads

    class ServiceAdapter(logging.LoggerAdapter):
        def process(self, msg, kwargs):
            extra = kwargs.setdefault("extra", {})
            extra.setdefault("service", service)
            extra.setdefault("correlation_id", extra.get("correlation_id", "-"))
            extra.setdefault("job_id", extra.get("job_id", "-"))
            return msg, kwargs

    logging.serviceLogger = lambda name: ServiceAdapter(logging.getLogger(name), {})  # type: ignore[attr-defined]


def get_logger(name: str) -> logging.Logger:
    return logging.getLogger(name)
