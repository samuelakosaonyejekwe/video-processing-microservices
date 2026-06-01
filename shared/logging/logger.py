import contextvars
import logging
import os
import sys

# Request/job-scoped context propagated into every log record by _ContextFilter.
_correlation_id_var: contextvars.ContextVar[str] = contextvars.ContextVar(
    "correlation_id", default="-"
)
_job_id_var: contextvars.ContextVar[str] = contextvars.ContextVar(
    "job_id", default="-"
)


def set_correlation_id(value: str | None) -> None:
    _correlation_id_var.set(value or "-")


def get_correlation_id() -> str:
    return _correlation_id_var.get()


def set_job_id(value: str | None) -> None:
    _job_id_var.set(value or "-")


class _ContextFilter(logging.Filter):
    """Inject service / correlation_id / job_id onto every record.

    The JSON formatter references these fields; without this filter they would
    be missing from records emitted by ordinary loggers, and the correlation id
    set by the request middleware would never reach the logs.
    """

    def __init__(self, service: str):
        super().__init__()
        self._service = service

    def filter(self, record: logging.LogRecord) -> bool:
        if not hasattr(record, "service"):
            record.service = self._service
        if not hasattr(record, "correlation_id"):
            record.correlation_id = _correlation_id_var.get()
        if not hasattr(record, "job_id"):
            record.job_id = _job_id_var.get()
        return True


def configure_logging(service_name: str | None = None) -> None:
    level_name = os.getenv("LOG_LEVEL", "INFO").upper()
    level = getattr(logging, level_name, logging.INFO)
    service = service_name or os.getenv("APP_NAME", "video-converter")

    context_filter = _ContextFilter(service)

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
                logging.Formatter(
                    "%(asctime)s %(levelname)s %(name)s "
                    "[%(correlation_id)s] %(message)s"
                )
            )
    else:
        handler = logging.StreamHandler(sys.stdout)
        handler.setFormatter(
            logging.Formatter(
                "%(asctime)s %(levelname)s %(name)s [%(correlation_id)s] %(message)s"
            )
        )

    handler.addFilter(context_filter)

    root = logging.getLogger()
    root.handlers.clear()
    root.addHandler(handler)
    root.setLevel(level)


def get_logger(name: str) -> logging.Logger:
    return logging.getLogger(name)
