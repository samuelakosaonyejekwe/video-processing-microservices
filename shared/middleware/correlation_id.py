import uuid

from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request

from shared.logging.logger import set_correlation_id


class CorrelationIdMiddleware(BaseHTTPMiddleware):
    HEADER = "X-Correlation-ID"

    async def dispatch(self, request: Request, call_next):
        correlation_id = request.headers.get(self.HEADER) or str(uuid.uuid4())
        request.state.correlation_id = correlation_id
        # Propagate into the logging context so every record in this request
        # carries the correlation id.
        set_correlation_id(correlation_id)

        response = await call_next(request)
        response.headers[self.HEADER] = correlation_id
        return response
