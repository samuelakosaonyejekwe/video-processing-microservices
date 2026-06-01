import logging
import signal
import sys
import threading
from typing import Callable

logger = logging.getLogger(__name__)

_shutdown_handlers: list[Callable[[], None]] = []
_registered = False
_shutting_down = False
_lock = threading.Lock()


def register_shutdown_handler(handler: Callable[[], None]) -> None:
    with _lock:
        _shutdown_handlers.append(handler)
        _ensure_signal_handlers()


def _run_shutdown_handlers() -> None:
    for handler in reversed(_shutdown_handlers):
        try:
            handler()
        except Exception as error:
            logger.warning("Shutdown handler failed: %s", error)


def _ensure_signal_handlers() -> None:
    global _registered
    if _registered:
        return

    def _handle(signum, frame):  # noqa: ARG001
        global _shutting_down
        with _lock:
            if _shutting_down:
                # Second signal during shutdown: force-exit immediately.
                sys.exit(128 + int(signum))
            _shutting_down = True

        logger.info("Received signal %s; running shutdown handlers", signum)
        _run_shutdown_handlers()
        # Actually terminate — handlers alone don't stop the process, and
        # without this the worker would hang until k8s SIGKILLs it.
        sys.exit(0)

    signal.signal(signal.SIGTERM, _handle)
    signal.signal(signal.SIGINT, _handle)
    _registered = True
