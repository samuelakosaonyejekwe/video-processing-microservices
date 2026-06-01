import os

from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request


def _hsts_enabled() -> bool:
    # HSTS is only meaningful over HTTPS; enable in production by default.
    default = "true" if os.getenv("APP_ENV", "production") == "production" else "false"
    return os.getenv("SECURITY_HSTS_ENABLED", default).lower() in ("1", "true", "yes")


class SecurityHeadersMiddleware(BaseHTTPMiddleware):
    """Attach baseline security response headers to every response."""

    def __init__(self, app, *, hsts_max_age: int = 31536000):
        super().__init__(app)
        self._hsts_max_age = hsts_max_age

    async def dispatch(self, request: Request, call_next):
        response = await call_next(request)

        headers = response.headers
        headers.setdefault("X-Content-Type-Options", "nosniff")
        headers.setdefault("X-Frame-Options", "DENY")
        headers.setdefault("Referrer-Policy", "no-referrer")
        headers.setdefault(
            "Content-Security-Policy",
            "default-src 'none'; frame-ancestors 'none'",
        )

        if _hsts_enabled():
            headers.setdefault(
                "Strict-Transport-Security",
                f"max-age={self._hsts_max_age}; includeSubDomains",
            )

        return response
