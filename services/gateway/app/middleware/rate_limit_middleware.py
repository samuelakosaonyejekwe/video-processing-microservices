import os

from fastapi import Request
from fastapi.responses import JSONResponse
from starlette.middleware.base import BaseHTTPMiddleware

from app.config import APP_ENV, RATE_LIMIT_MAX_REQUESTS, RATE_LIMIT_WINDOW_SECONDS
from shared.security.rate_limit import is_rate_limited, rate_limit_key


class RateLimitMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        if APP_ENV == "test":
            return await call_next(request)

        if request.url.path in ("/health", "/health/", "/health/ready", "/metrics"):
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

        return await call_next(request)
