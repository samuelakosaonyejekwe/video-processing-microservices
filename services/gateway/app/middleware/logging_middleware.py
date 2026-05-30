import logging
from fastapi import Request
from starlette.middleware.base import BaseHTTPMiddleware

logging.basicConfig(level=logging.INFO)

logger = logging.getLogger("gateway")


class LoggingMiddleware(BaseHTTPMiddleware):

    async def dispatch(self, request: Request, call_next):

        logger.info(f"{request.method} request to {request.url.path}")

        response = await call_next(request)

        return response
