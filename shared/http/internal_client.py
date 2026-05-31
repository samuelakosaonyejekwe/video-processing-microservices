import os
from typing import Any

import httpx


def internal_http_client(**kwargs: Any) -> httpx.AsyncClient:
    ca_path = os.getenv("INTERNAL_TLS_CA_PATH", "").strip()
    verify: bool | str = ca_path if ca_path else True
    return httpx.AsyncClient(timeout=kwargs.pop("timeout", 30.0), verify=verify, **kwargs)
