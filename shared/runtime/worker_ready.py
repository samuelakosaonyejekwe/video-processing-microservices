import threading
from pathlib import Path


class WorkerReadyMarker:
    def __init__(self, path: str | Path = "/tmp/worker-ready"):
        self.path = Path(path)
        self.event = threading.Event()

    def mark_ready(self) -> None:
        self.path.touch()
        self.event.set()

    def clear(self) -> None:
        self.path.unlink(missing_ok=True)
        self.event.clear()

    def wait_until_ready(self, timeout: float | None = 30.0) -> bool:
        return self.event.wait(timeout=timeout)
