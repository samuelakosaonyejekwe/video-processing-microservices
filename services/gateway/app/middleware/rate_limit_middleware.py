import time
from collections import defaultdict
from threading import Lock

from fastapi import Request
from fastapi.responses import JSONResponse

from starlette.middleware.base import BaseHTTPMiddleware

from app.config import (
    RATE_LIMIT_MAX_REQUESTS,
    RATE_LIMIT_WINDOW_SECONDS,
)


class RateLimitMiddleware(BaseHTTPMiddleware):

    def __init__(self, app):

        super().__init__(app)

        self._requests = defaultdict(list)

        self._lock = Lock()

    async def dispatch(self, request: Request, call_next):

        if request.url.path in ("/health", "/health/", "/metrics"):
            return await call_next(request)

        client_ip = request.client.host if request.client else "unknown"

        now = time.time()

        with self._lock:
            window_start = now - RATE_LIMIT_WINDOW_SECONDS

            timestamps = self._requests[client_ip]

            self._requests[client_ip] = [ts for ts in timestamps if ts > window_start]

            if len(self._requests[client_ip]) >= RATE_LIMIT_MAX_REQUESTS:
                return JSONResponse(
                    status_code=429,
                    content={"detail": "Rate limit exceeded"},
                )

            self._requests[client_ip].append(now)

        return await call_next(request)
