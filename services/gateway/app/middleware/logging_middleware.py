import logging
import time

from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request

logger = logging.getLogger("gateway.request")


class LoggingMiddleware(BaseHTTPMiddleware):
    """Structured per-request access logging with correlation-ID injection.

    Runs inside CorrelationIdMiddleware so ``request.state.correlation_id`` is
    populated. Emits structured records (via the `extra` dict) rather than
    interpolated f-strings so log fields stay machine-parseable, and never calls
    logging.basicConfig() — handler configuration is owned by configure_logging.
    """

    async def dispatch(self, request: Request, call_next):
        start = time.perf_counter()
        correlation_id = getattr(
            request.state, "correlation_id", None
        ) or request.headers.get("X-Correlation-ID", "-")

        response = await call_next(request)

        duration_ms = round((time.perf_counter() - start) * 1000, 2)
        logger.info(
            "request completed",
            extra={
                "correlation_id": correlation_id,
                "http_method": request.method,
                "http_path": request.url.path,
                "http_status": response.status_code,
                "duration_ms": duration_ms,
            },
        )
        return response
