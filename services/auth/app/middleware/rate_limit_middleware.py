import os

from fastapi import Request
from fastapi.responses import JSONResponse
from starlette.middleware.base import BaseHTTPMiddleware

from app.config import APP_ENV
from shared.security.client_ip import get_client_ip
from shared.security.rate_limit import is_rate_limited

RATE_LIMIT_MAX_REQUESTS = int(os.getenv("AUTH_RATE_LIMIT_MAX_REQUESTS", "20"))
RATE_LIMIT_WINDOW_SECONDS = int(
    os.getenv("AUTH_RATE_LIMIT_WINDOW_SECONDS", "60")
)

PROTECTED_PREFIXES = ("/auth/login", "/auth/register", "/auth/refresh")


class AuthRateLimitMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        if APP_ENV == "test":
            return await call_next(request)

        path = request.url.path
        if not any(path.startswith(prefix) for prefix in PROTECTED_PREFIXES):
            return await call_next(request)

        client_host = get_client_ip(request)
        key = f"auth:{client_host}:{path}"

        if is_rate_limited(
            key,
            max_requests=RATE_LIMIT_MAX_REQUESTS,
            window_seconds=RATE_LIMIT_WINDOW_SECONDS,
        ):
            return JSONResponse(
                status_code=429,
                content={"detail": "Too many authentication attempts"},
            )

        return await call_next(request)
