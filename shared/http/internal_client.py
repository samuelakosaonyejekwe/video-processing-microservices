import os
from typing import Any

import httpx


def internal_http_client(**kwargs: Any) -> httpx.AsyncClient:
    ca_path = os.getenv("INTERNAL_TLS_CA_PATH", "").strip()
    verify: bool | str = True
    if ca_path and os.path.isfile(ca_path):
        verify = ca_path
    return httpx.AsyncClient(timeout=kwargs.pop("timeout", 30.0), verify=verify, **kwargs)
