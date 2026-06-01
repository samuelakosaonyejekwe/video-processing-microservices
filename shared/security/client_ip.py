import os

from starlette.requests import Request


def _trust_proxy_enabled() -> bool:
    return os.getenv("TRUST_PROXY_HEADERS", "false").lower() in ("1", "true", "yes")


def _trusted_hop_count() -> int:
    """Number of trusted proxies between the client and this service."""
    try:
        hops = int(os.getenv("TRUSTED_PROXY_HOP_COUNT", "1"))
    except ValueError:
        hops = 1
    return max(hops, 1)


def get_client_ip(request: Request) -> str:
    """Resolve the client IP, honoring trusted proxy headers when enabled.

    X-Forwarded-For is client-controllable: anyone can prepend arbitrary
    entries to spoof their source IP and defeat per-IP rate limiting. We only
    trust the address inserted by our own proxy layer. With ``hops`` trusted
    proxies in front of us, the genuine client IP is the ``hops``-th entry from
    the right of the chain. A chain shorter than the trusted hop count means the
    header was forged, so we fall back to the direct peer address.
    """
    if request.client and request.client.host:
        direct_ip = request.client.host
    else:
        direct_ip = "unknown"

    if not _trust_proxy_enabled():
        return direct_ip

    forwarded_for = request.headers.get("X-Forwarded-For", "")
    if forwarded_for:
        chain = [ip.strip() for ip in forwarded_for.split(",") if ip.strip()]
        hops = _trusted_hop_count()
        if len(chain) >= hops:
            return chain[-hops]
        return direct_ip

    # Intentionally do NOT fall back to X-Real-IP: it is just as client-spoofable
    # as X-Forwarded-For but carries no hop information, so an attacker could
    # forge it to rotate the rate-limit key. Trust only the validated XFF hop or
    # the direct peer address.
    return direct_ip
