import os

from starlette.requests import Request


def get_client_ip(request: Request) -> str:
    """Resolve the client IP, honoring trusted proxy headers when enabled."""
    if request.client and request.client.host:
        direct_ip = request.client.host
    else:
        direct_ip = "unknown"

    if os.getenv("TRUST_PROXY_HEADERS", "false").lower() not in (
        "1",
        "true",
        "yes",
    ):
        return direct_ip

    forwarded_for = request.headers.get("X-Forwarded-For", "")
    if forwarded_for:
        return forwarded_for.split(",")[0].strip()

    real_ip = request.headers.get("X-Real-IP", "").strip()
    if real_ip:
        return real_ip

    return direct_ip
