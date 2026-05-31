import signal
import threading
from typing import Callable

_shutdown_handlers: list[Callable[[], None]] = []
_registered = False
_lock = threading.Lock()


def register_shutdown_handler(handler: Callable[[], None]) -> None:
    with _lock:
        _shutdown_handlers.append(handler)
        _ensure_signal_handlers()


def _run_shutdown_handlers() -> None:
    for handler in reversed(_shutdown_handlers):
        try:
            handler()
        except Exception:
            pass


def _ensure_signal_handlers() -> None:
    global _registered
    if _registered:
        return

    def _handle(signum, frame):  # noqa: ARG001
        _run_shutdown_handlers()

    signal.signal(signal.SIGTERM, _handle)
    signal.signal(signal.SIGINT, _handle)
    _registered = True
