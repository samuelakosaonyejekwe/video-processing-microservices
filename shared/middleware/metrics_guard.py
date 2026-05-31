import os
from ipaddress import ip_address, ip_network

from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import JSONResponse

_PRIVATE_NETWORKS = (
    ip_network("10.0.0.0/8"),
    ip_network("172.16.0.0/12"),
    ip_network("192.168.0.0/16"),
    ip_network("127.0.0.0/8"),
)


def _client_is_internal(request: Request) -> bool:
    if not request.client or not request.client.host:
        return False
    try:
        address = ip_address(request.client.host)
    except ValueError:
        return False
    return any(address in network for network in _PRIVATE_NETWORKS)


class MetricsGuardMiddleware(BaseHTTPMiddleware):
    """Restrict /metrics to internal scrapers or an optional bearer token."""

    async def dispatch(self, request: Request, call_next):
        if request.url.path != "/metrics":
            return await call_next(request)

        if os.getenv("METRICS_PUBLIC", "false").lower() in ("1", "true", "yes"):
            return await call_next(request)

        expected_token = os.getenv("METRICS_TOKEN", "").strip()
        authorization = request.headers.get("Authorization", "")
        if expected_token and authorization == f"Bearer {expected_token}":
            return await call_next(request)

        if _client_is_internal(request):
            return await call_next(request)

        return JSONResponse(status_code=403, content={"detail": "Metrics forbidden"})
