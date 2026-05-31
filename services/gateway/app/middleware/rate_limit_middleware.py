import time
from collections import defaultdict
from threading import Lock

from fastapi import Request
from fastapi.responses import JSONResponse
from starlette.middleware.base import BaseHTTPMiddleware

from app.config import RATE_LIMIT_MAX_REQUESTS, RATE_LIMIT_WINDOW_SECONDS
from shared.security.rate_limit import is_rate_limited, rate_limit_key


class RateLimitMiddleware(BaseHTTPMiddleware):

    def __init__(self, app):

        super().__init__(app)

        self._requests = defaultdict(list)

        self._lock = Lock()

    async def dispatch(self, request: Request, call_next):

        if request.url.path in ("/health", "/health/", "/metrics"):
            return await call_next(request)

        client_ip = request.client.host if request.client else "unknown"
        key = rate_limit_key(client_ip, request.url.path)

        if is_rate_limited(
            key,
            max_requests=RATE_LIMIT_MAX_REQUESTS,
            window_seconds=RATE_LIMIT_WINDOW_SECONDS,
        ):
            return JSONResponse(
                status_code=429,
                content={"detail": "Rate limit exceeded"},
            )

        now = time.time()

        with self._lock:
            window_start = now - RATE_LIMIT_WINDOW_SECONDS

            timestamps = self._requests[key]

            self._requests[key] = [ts for ts in timestamps if ts > window_start]

            if len(self._requests[key]) >= RATE_LIMIT_MAX_REQUESTS:
                return JSONResponse(
                    status_code=429,
                    content={"detail": "Rate limit exceeded"},
                )

            self._requests[key].append(now)

        return await call_next(request)
