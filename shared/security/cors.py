"""Shared CORS configuration.

Browsers only ever send a known, finite set of request headers to these APIs,
so we enumerate them explicitly instead of using the wildcard "*", which would
otherwise allow any header and weaken the same-origin protections.
"""

ALLOWED_CORS_HEADERS = [
    "Accept",
    "Authorization",
    "Content-Type",
    "Origin",
    "X-Requested-With",
    "X-Correlation-ID",
]
