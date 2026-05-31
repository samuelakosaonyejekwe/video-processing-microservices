import time
from collections import defaultdict
from threading import Lock

from fastapi import Request
from fastapi.responses import JSONResponse
from starlette.middleware.base import BaseHTTPMiddleware

from app.config import APP_ENV

RATE_LIMIT_MAX_REQUESTS = int(
    __import__("os").getenv("AUTH_RATE_LIMIT_MAX_REQUESTS", "20")
)
RATE_LIMIT_WINDOW_SECONDS = int(
    __import__("os").getenv("AUTH_RATE_LIMIT_WINDOW_SECONDS", "60")
)

PROTECTED_PREFIXES = ("/auth/login", "/auth/register", "/auth/refresh")


class AuthRateLimitMiddleware(BaseHTTPMiddleware):
    def __init__(self, app):
        super().__init__(app)
        self._requests = defaultdict(list)
        self._lock = Lock()

    async def dispatch(self, request: Request, call_next):
        if APP_ENV == "test":
            return await call_next(request)

        path = request.url.path
        if not any(path.startswith(prefix) for prefix in PROTECTED_PREFIXES):
            return await call_next(request)

        client_host = request.client.host if request.client else "unknown"
        key = f"{client_host}:{path}"
        now = time.time()

        with self._lock:
            window_start = now - RATE_LIMIT_WINDOW_SECONDS
            self._requests[key] = [
                timestamp
                for timestamp in self._requests[key]
                if timestamp >= window_start
            ]

            if len(self._requests[key]) >= RATE_LIMIT_MAX_REQUESTS:
                return JSONResponse(
                    status_code=429,
                    content={"detail": "Too many authentication attempts"},
                )

            self._requests[key].append(now)

        return await call_next(request)
